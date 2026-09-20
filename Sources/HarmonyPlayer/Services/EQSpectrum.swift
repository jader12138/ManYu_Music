import Accelerate
import Combine
import Foundation

// MARK: - 采样环形缓冲（音频线程写 / UI 线程读）

/// 跨 tap 共享的单声道采样环形缓冲：
/// 音频 tap 的实时线程把下混后的采样写进来，频谱分析定时器在主线程取走。
/// 固定容量、预分配内存，写入侧只有锁 + 拷贝，满足近实时约束。
final class EQSpectrumRing {
    private let capacity = 16_384
    private var storage: [Float]
    private var writeIndex = 0
    private let lock = NSLock()
    /// 累计写入样本数；读取侧用它判断有无新数据（暂停时停止推进）。
    private(set) var writeCount: UInt64 = 0
    /// 由 tap prepare 回调写入（同一时刻只有一个引擎出声）。
    var sampleRate: Double = 48_000

    init() {
        storage = .init(repeating: 0, count: capacity)
    }

    /// 追加写入 count 个单声道样本（跨边界自动回绕）。
    func write(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        storage.withUnsafeMutableBufferPointer { dest in
            var offset = 0
            var remaining = count
            while remaining > 0 {
                let chunk = min(remaining, capacity - writeIndex)
                dest.baseAddress!
                    .advanced(by: writeIndex)
                    .update(from: samples + offset, count: chunk)
                writeIndex = (writeIndex + chunk) % capacity
                offset += chunk
                remaining -= chunk
            }
        }
        writeCount &+= UInt64(count)
    }

    /// 取最近的 out.count 个样本（不足的部分以 0 填充在开头），返回实际可用数。
    func latest(into out: inout [Float]) -> Int {
        let needed = out.count
        guard needed > 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        let available = Int(min(UInt64(capacity), writeCount))
        let copied = min(needed, available)
        if copied < needed {
            for index in 0..<(needed - copied) { out[index] = 0 }
        }
        var start = writeIndex - copied
        if start < 0 { start += capacity }
        storage.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dest in
                var offset = needed - copied
                var remaining = copied
                while remaining > 0 {
                    let chunk = min(remaining, capacity - start)
                    dest.baseAddress!
                        .advanced(by: offset)
                        .update(from: src.baseAddress! + start, count: chunk)
                    start = (start + chunk) % capacity
                    offset += chunk
                    remaining -= chunk
                }
            }
        }
        return copied
    }
}

// MARK: - 实时频谱分析器（主线程）

/// 实时频谱：30fps 定时器从环形缓冲取最新 4096 样本，
/// Hann 加窗 + vDSP 实数 FFT，按对数频率轴（20Hz ~ 20kHz）聚合成
/// 96 点 dB 曲线；叠加高频倾斜补偿（自然音乐高频能量低，
/// 不补偿则对数轴右半边常年贴地）与幂次对比拉伸（峰更突出、谷更深），
/// 归一化到 0...1 后发布给 Canvas 绘制出高低错落的"山峰"轮廓。
@MainActor
final class EQSpectrumAnalyzer: ObservableObject {
    @Published private(set) var levels: [Double] =
        [Double](repeating: 0, count: EQSpectrumAnalyzer.pointCount)
    /// 远山影：跟随主线但更矮、衰减更慢的第二层轮廓，形成层叠山影。
    @Published private(set) var trailing: [Double] =
        [Double](repeating: 0, count: EQSpectrumAnalyzer.pointCount)

    static let pointCount = 96
    static let minHz: Double = 20
    static let maxHz: Double = 20_000
    /// dB 归一化窗口：低于下限视为静音，高于上限视为满格。
    private static let dBMin = -72.0
    private static let dBMax = -6.0
    /// 高频倾斜补偿上限（dB）：按对数频率位置线性抬升高频。
    private static let trebleTiltDB = 10.0
    /// 对比拉伸幂次：>1 时中低电平被压低、峰值保留，拉大峰谷反差。
    private static let contrastExponent = 1.35

    private weak var ring: EQSpectrumRing?
    private var timer: Timer?

    private let fftSize = 4096
    private var isPipelineReady = false
    private var fftSetup: FFTSetup?
    private var log2n: vDSP_Length { vDSP_Length(12) }
    private var window: [Float] = []
    private var windowed: [Float] = []
    private var samples: [Float] = []
    private var realPart: [Float] = []
    private var imagPart: [Float] = []
    private var magnitudes: [Float] = []
    private var lastWriteCount: UInt64 = 0
    private var hasReceivedData = false

    deinit {
        timer?.invalidate()
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func connect(to ring: EQSpectrumRing) {
        self.ring = ring
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func preparePipelineIfNeeded() {
        guard !isPipelineReady else { return }
        let half = fftSize / 2
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(FFT_RADIX2))
        window = .init(repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
        windowed = .init(repeating: 0, count: fftSize)
        samples = .init(repeating: 0, count: fftSize)
        realPart = .init(repeating: 0, count: half)
        imagPart = .init(repeating: 0, count: half)
        magnitudes = .init(repeating: 0, count: half)
        isPipelineReady = fftSetup != nil
    }

    private func tick() {
        preparePipelineIfNeeded()
        guard isPipelineReady, let ring else { return }

        if ring.writeCount == lastWriteCount {
            // 没有新数据（暂停或空转）：谱线与远山影平滑衰减归零。
            if hasReceivedData {
                levels = levels.map { max(0, $0 * 0.8 - 0.004) }
                trailing = trailing.map { max(0, $0 * 0.88 - 0.003) }
            }
            return
        }
        lastWriteCount = ring.writeCount
        hasReceivedData = true

        _ = ring.latest(into: &samples)
        let half = fftSize / 2

        // Hann 加窗（逐元素相乘）
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        realPart.withUnsafeMutableBufferPointer { realBuffer in
            imagPart.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imagBuffer.baseAddress!
                )
                windowed.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: half
                    ) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup!, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // 对数频率轴聚合：每个点取 [f0, f1) 频段内的峰值。
        // dB 域叠加高频倾斜补偿（对数频率位置线性 +0 ~ +10dB），
        // 归一化后再做幂次对比拉伸，让峰更突出、谷更深，呈山峰错落。
        let binHz = ring.sampleRate / Double(fftSize)
        let ratio = Self.maxHz / Self.minHz
        let logSpan = log(Self.maxHz / Self.minHz)
        var newLevels = [Double](repeating: 0.0, count: EQSpectrumAnalyzer.pointCount)
        for index in 0..<EQSpectrumAnalyzer.pointCount {
            let f0 = Self.minHz * pow(ratio, Double(index) / Double(EQSpectrumAnalyzer.pointCount))
            let f1 = Self.minHz * pow(ratio, Double(index + 1) / Double(EQSpectrumAnalyzer.pointCount))
            let bin0 = max(1, Int(f0 / binHz))
            let bin1 = max(bin0 + 1, min(half, Int(f1 / binHz)))
            var peak: Float = 0
            for bin in bin0..<min(bin1, half) where magnitudes[bin] > peak {
                peak = magnitudes[bin]
            }
            let dB = 20 * log10(Double(max(peak, 1e-7)))
            let tilt = Self.trebleTiltDB * log(max(f0, Self.minHz) / Self.minHz) / logSpan
            let normalized = (dB + tilt - Self.dBMin) / (Self.dBMax - Self.dBMin)
            let clamped = min(max(normalized, 0), 1)
            newLevels[index] = pow(clamped, Self.contrastExponent)
        }

        // 快攻慢放：新值更高立刻跟上，回落时保留余晖（比旧版更快落谷，
        // 避免慢放把所有点拖成一片高原）。
        levels = zip(newLevels, levels).map { max($0, $1 * 0.75) }

        // 远山影：取主线的矮化快照，慢速衰减——峰过之后山影缓缓退去。
        trailing = zip(levels, trailing).map { max($0 * 0.55, $1 * 0.94 - 0.002) }
    }
}
