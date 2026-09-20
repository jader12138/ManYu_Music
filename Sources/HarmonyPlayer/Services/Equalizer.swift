import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import MediaToolbox

// MARK: - 均衡器参数模型（线程安全）

/// 十段图形均衡器：31Hz ~ 16kHz，各段增益 -12 ~ +12 dB。
/// 参数由 UI 线程写入、音频 tap 的实时线程读取，内部用锁保护；
/// revision 号让 tap 检测到参数变化后在下一帧前重建 biquad 系数。
/// 内置预设 + 自定义命名预设（UserDefaults JSON 持久化）。
final class Equalizer {
    static let bandFrequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let bandLabels: [String] = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let bandCount = 10
    static let gainRange: ClosedRange<Double> = -12...12

    struct Preset: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var gains: [Double]
    }

    /// 手动微调（不属于任何预设）时的虚拟预设 ID。
    static let customCurveID = "custom"

    static let flat = Preset(id: "flat", name: "平直", gains: .init(repeating: 0, count: bandCount))
    static let builtInPresets: [Preset] = [
        flat,
        Preset(id: "pop", name: "流行", gains: [3, 4, 2, 0, -1, -1, 0, 2, 3, 4]),
        Preset(id: "classical", name: "古典", gains: [4, 3, 1, 0, 0, 0, 0, 0, 2, 3]),
        Preset(id: "rock", name: "摇滚", gains: [5, 4, 2, -1, -2, -1, 2, 4, 4, 3]),
        Preset(id: "vocal", name: "人声", gains: [-3, -2, 0, 2, 4, 4, 3, 1, -1, -2]),
    ]

    // UserDefaults 键
    static let enabledKey = "ManyuMusic.eqEnabled"
    static let selectedPresetIDKey = "ManyuMusic.eqSelectedPresetID"
    static let customPresetsKey = "ManyuMusic.eqCustomPresets"
    private static let gainsKey = "ManyuMusic.eqGains"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var storedGains: [Double]
    private var storedRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.array(forKey: Self.gainsKey) as? [Double]
        let curve = (saved?.count == Self.bandCount) ? saved! : Self.flat.gains
        self.storedGains = curve.map {
            min(max($0, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        }
    }

    // MARK: 开关 / 预设选择（与 gapless 等设置同款：读时兜底、写即持久化）

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var selectedPresetID: String {
        get { defaults.string(forKey: Self.selectedPresetIDKey) ?? Self.flat.id }
        set { defaults.set(newValue, forKey: Self.selectedPresetIDKey) }
    }

    var customPresets: [Preset] {
        get {
            guard let data = defaults.data(forKey: Self.customPresetsKey) else { return [] }
            return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.customPresetsKey)
            }
        }
    }

    // MARK: 当前曲线（音频线程读）

    /// 当前 10 段增益（dB）。音频 tap 通过 revision 感知变化。
    var gains: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storedGains
    }

    var revision: Int {
        lock.lock(); defer { lock.unlock() }
        return storedRevision
    }

    func setGains(_ newGains: [Double]) {
        precondition(newGains.count == Self.bandCount, "EQ 曲线必须是 10 段")
        var clamped: [Double] = []
        lock.lock()
        clamped = newGains.map {
            min(max($0, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        }
        storedGains = clamped
        storedRevision += 1
        lock.unlock()
        defaults.set(clamped, forKey: Self.gainsKey)
    }

    func setGain(at index: Int, to value: Double) {
        var g = gains
        g[index] = value
        setGains(g)
    }

    // MARK: 预设操作

    /// 应用预设：写曲线 + 记住选中 ID。
    func apply(preset: Preset) {
        selectedPresetID = preset.id
        setGains(preset.gains)
    }

    /// 把当前曲线保存为命名自定义预设，并选中它。
    func saveCustomPreset(named name: String) -> Preset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = Preset(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "自定义" : trimmed,
            gains: gains
        )
        var list = customPresets
        list.append(preset)
        customPresets = list
        selectedPresetID = preset.id
        return preset
    }

    func removeCustomPreset(id: String) {
        customPresets = customPresets.filter { $0.id != id }
        if selectedPresetID == id {
            selectedPresetID = Self.flat.id
        }
    }

    /// 当前选中的预设对象（自定义曲线时返回 nil）。
    func selectedPreset() -> Preset? {
        let id = selectedPresetID
        return Self.builtInPresets.first { $0.id == id }
            ?? customPresets.first { $0.id == id }
    }

    /// 预设选择器里显示的名字。
    func selectedPresetName() -> String {
        selectedPreset()?.name ?? "自定义"
    }

    // MARK: RBJ biquad 系数设计

    struct Section {
        var b0, b1, b2, a1, a2: Double
        static let identity = Section(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    }

    /// 峰值（peaking EQ）段。
    static func peaking(f0: Double, sampleRate: Double, gainDB: Double, q: Double) -> Section {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * .pi * f0 / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw0 = cos(w0)
        let a0 = 1 + alpha / a
        return Section(
            b0: (1 + alpha * a) / a0,
            b1: (-2 * cosw0) / a0,
            b2: (1 - alpha * a) / a0,
            a1: (-2 * cosw0) / a0,
            a2: (1 - alpha / a) / a0
        )
    }

    /// 低架（low shelf）段，用于最低频段。
    static func lowShelf(f0: Double, sampleRate: Double, gainDB: Double) -> Section {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * .pi * f0 / sampleRate
        let alpha = sin(w0) / 2 * sqrt((a + 1 / a) * 2 - 1)  // S = 1
        let cosw0 = cos(w0)
        let twoSqrtAAlpha = 2 * sqrt(a) * alpha
        let a0 = (a + 1) + (a - 1) * cosw0 + twoSqrtAAlpha
        return Section(
            b0: (a * ((a + 1) - (a - 1) * cosw0 + twoSqrtAAlpha)) / a0,
            b1: (2 * a * ((a - 1) - (a + 1) * cosw0)) / a0,
            b2: (a * ((a + 1) - (a - 1) * cosw0 - twoSqrtAAlpha)) / a0,
            a1: (-2 * ((a - 1) + (a + 1) * cosw0)) / a0,
            a2: ((a + 1) + (a - 1) * cosw0 - twoSqrtAAlpha) / a0
        )
    }

    /// 高架（high shelf）段，用于最高频段。
    static func highShelf(f0: Double, sampleRate: Double, gainDB: Double) -> Section {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * .pi * f0 / sampleRate
        let alpha = sin(w0) / 2 * sqrt((a + 1 / a) * 2 - 1)
        let cosw0 = cos(w0)
        let twoSqrtAAlpha = 2 * sqrt(a) * alpha
        let a0 = (a + 1) - (a - 1) * cosw0 + twoSqrtAAlpha
        return Section(
            b0: (a * ((a + 1) + (a - 1) * cosw0 + twoSqrtAAlpha)) / a0,
            b1: (-2 * a * ((a - 1) + (a + 1) * cosw0)) / a0,
            b2: (a * ((a + 1) + (a - 1) * cosw0 - twoSqrtAAlpha)) / a0,
            a1: (2 * ((a - 1) - (a + 1) * cosw0)) / a0,
            a2: ((a + 1) - (a - 1) * cosw0 - twoSqrtAAlpha) / a0
        )
    }

    /// 依当前曲线设计 10 个 biquad 段：两端 shelf、中间 peaking。
    func coefficients(sampleRate: Double) -> [Section] {
        let g = gains
        var sections: [Section] = []
        sections.reserveCapacity(Self.bandCount)
        for (index, frequency) in Self.bandFrequencies.enumerated() {
            if g[index] == 0 {
                sections.append(.identity)
                continue
            }
            switch index {
            case 0:
                sections.append(Self.lowShelf(f0: frequency, sampleRate: sampleRate, gainDB: g[index]))
            case Self.bandCount - 1:
                sections.append(Self.highShelf(f0: frequency, sampleRate: sampleRate, gainDB: g[index]))
            default:
                sections.append(Self.peaking(f0: frequency, sampleRate: sampleRate, gainDB: g[index], q: 1.1))
            }
        }
        return sections
    }
}

// MARK: - 每个 tap 独立的滤波状态与实时处理

/// tap 上下文：共享的 Equalizer 参数 + 本 tap 独立的各段延迟状态。
/// prepare 回调确定采样率/声道数；process 回调在实时音频线程运行。
final class EQTapContext {
    let equalizer: Equalizer
    var sampleRate: Double = 48_000
    var channels = 2
    /// [声道][段] 的二阶状态（转置直接 II 型的 s1/s2）。
    var delays: [[(s1: Float, s2: Float)]] = []
    /// 缓存的 Float 系数 [段][b0,b1,b2,a1,a2]，与 equalizer.revision 对齐。
    var coeffs: [[Float]] = []
    var cachedRevision = -1

    init(equalizer: Equalizer) {
        self.equalizer = equalizer
    }

    func resetForPrepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = max(1, channels)
        rebuildDelays()
        cachedRevision = -1  // 强制下一帧按新采样率重建系数
    }

    func rebuildDelays() {
        delays = (0..<channels).map { _ in
            (0..<Equalizer.bandCount).map { _ in (s1: 0 as Float, s2: 0 as Float) }
        }
    }

    @inline(__always)
    private func cascade(_ input: Float, channel: Int) -> Float {
        var x = input
        for s in 0..<coeffs.count {
            let c = coeffs[s]
            var d = delays[channel][s]
            let y = c[0] * x + d.s1
            d.s1 = c[1] * x - c[3] * y + d.s2
            d.s2 = c[2] * x - c[4] * y
            delays[channel][s] = d
            x = y
        }
        return x
    }

    /// 参数变化时重建系数（在音频线程调用，代价仅 10 段三角函数，一次性）。
    private func refreshCoefficientsIfNeeded() {
        let rev = equalizer.revision
        guard rev != cachedRevision || coeffs.count != Equalizer.bandCount else { return }
        let sections = equalizer.coefficients(sampleRate: sampleRate)
        coeffs = sections.map { [$0.b0, $0.b1, $0.b2, $0.a1, $0.a2].map(Float.init) }
        cachedRevision = rev
        rebuildDelays()  // 参数变化后从零状态开始，避免旧状态残留
    }

    /// 就地处理 AudioBufferList。支持非交织（每声道一个 buffer）与交织两种布局。
    func process(bufferList pointer: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        refreshCoefficientsIfNeeded()

        // 平直曲线直接通过，不做任何乘加。
        let g = equalizer.gains
        if g.allSatisfy({ abs($0) < 0.001 }) { return }

        let list = UnsafeMutableAudioBufferListPointer(pointer)
        if list.count > 1 {
            // 非交织：每个 AudioBuffer 是一个声道的连续 PCM。
            for channel in 0..<min(list.count, delays.count) {
                let buffer = list[channel]
                guard let mData = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = mData.bindMemory(to: Float.self, capacity: count)
                for frame in 0..<min(count, frames) {
                    samples[frame] = cascade(samples[frame], channel: channel)
                }
            }
        } else if list.count == 1 {
            // 交织：单个 buffer，帧步长为声道数。
            let buffer = list[0]
            guard let mData = buffer.mData else { return }
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let total = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = mData.bindMemory(to: Float.self, capacity: total)
            let usable = min(total, frames * channelCount)
            for frame in 0..<(usable / channelCount) {
                for channel in 0..<channelCount {
                    let index = frame * channelCount + channel
                    let state = min(channel, delays.count - 1)
                    samples[index] = cascade(samples[index], channel: state)
                }
            }
        }
    }
}

// MARK: - MTAudioProcessingTap 胶水

/// 把 EQTapContext 挂进 AVPlayerItem 的音频管线：
/// AVMutableAudioMixInputParameters.audioTapProcessor。
enum EQTap {
    /// EQ 开启时为新 item 挂 tap（异步取音轨，完成后设置 audioMix）。
    static func attachIfEnabled(to item: AVPlayerItem, equalizer: Equalizer) {
        guard equalizer.isEnabled else { return }
        attach(to: item, equalizer: equalizer)
    }

    static func attach(to item: AVPlayerItem, equalizer: Equalizer) {
        item.asset.loadTracks(withMediaType: .audio) { tracks, _ in
            guard let track = tracks?.first, equalizer.isEnabled else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = makeTap(equalizer: equalizer)
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
    }

    static func detach(from item: AVPlayerItem?) {
        item?.audioMix = nil
    }

    /// 创建 tap（CM_RETURNS_RETAINED：+1 引用交给 ARC，
    /// 赋给 audioTapProcessor 属性后所有权归音频管线，finalize 回调释放上下文）。
    static func makeTap(equalizer: Equalizer) -> MTAudioProcessingTap {
        let contextPointer = Unmanaged
            .passRetained(EQTapContext(equalizer: equalizer))
            .toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: 0,
            clientInfo: contextPointer,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        var tapOut: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapOut
        )
        precondition(status == noErr, "MTAudioProcessingTapCreate 失败：\(status)")
        guard let tap = tapOut else {
            fatalError("MTAudioProcessingTapCreate 未返回 tap")
        }
        return tap
    }

    static func context(of tap: MTAudioProcessingTap) -> EQTapContext? {
        let storage = MTAudioProcessingTapGetStorage(tap)
        return Unmanaged<EQTapContext>.fromOpaque(storage).takeUnretainedValue()
    }
}

// MARK: C 回调（不能捕获上下文，一律经 tapStorage 传递）

private func tapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<EQTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func tapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let format = processingFormat.pointee
    EQTap.context(of: tap)?.resetForPrepare(
        sampleRate: format.mSampleRate,
        channels: Int(format.mChannelsPerFrame)
    )
}

private func tapUnprepare(_ tap: MTAudioProcessingTap) {}

private func tapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )
    guard status == noErr else { return }
    EQTap.context(of: tap)?.process(bufferList: bufferListInOut, frames: Int(numberFrames))
}
