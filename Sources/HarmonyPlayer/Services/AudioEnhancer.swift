import AudioToolbox
import CoreAudioTypes
import Foundation

// MARK: - 音效增强参数模型（线程安全）

/// 音效增强：频率调节（7 段滤波 + 动态压缩）、空间效果（早反射/立体声扩展/混响）、
/// 输出控制（输出增益/声道平衡）。参数由 UI 线程写入、音频 tap 实时线程读取，
/// 内部用锁保护 + revision 号驱动滤波系数重建；全部参数 UserDefaults 持久化。
/// 挂在 Equalizer 之下共用同一个音频 tap（EQ 处理之后级联，两开关互相独立）。
final class AudioEnhancer: ObservableObject {
    static let percentRange: ClosedRange<Double> = 0...100
    static let outputGainRange: ClosedRange<Double> = -12...12
    static let balanceRange: ClosedRange<Double> = -1...1

    /// 音频线程每帧一次的参数快照（锁内拷贝，避免音频线程反复进锁）。
    struct Snapshot {
        var enabled = false
        var lowBoost: Double = 0      // 低频提升（60Hz low shelf）
        var bassEnhance: Double = 0   // 低音增强（100Hz peaking）
        var warmth: Double = 0        // 温暖感（250Hz peaking）
        var vocalEnhance: Double = 0  // 人声增强（3kHz peaking）
        var presence: Double = 0      // 临场感（4kHz peaking）
        var clarity: Double = 0       // 清晰度（8kHz peaking）
        var trebleBoost: Double = 0   // 高频提升（8kHz high shelf）
        var dynamics: Double = 0      // 动态增强（压缩动态范围）
        var ambience: Double = 0      // 环境感（早反射空间感）
        var surround: Double = 0      // 环绕声（立体声扩展 M/S）
        var reverb: Double = 0        // 环境混响（Schroeder 混响尾）
        var outputGainDB: Double = 0  // 输出增益
        var balance: Double = 0       // 声道平衡（-1 左 ... +1 右）
    }

    @Published private(set) var enabled = false
    @Published private(set) var lowBoost: Double = 0
    @Published private(set) var bassEnhance: Double = 0
    @Published private(set) var warmth: Double = 0
    @Published private(set) var vocalEnhance: Double = 0
    @Published private(set) var presence: Double = 0
    @Published private(set) var clarity: Double = 0
    @Published private(set) var trebleBoost: Double = 0
    @Published private(set) var dynamics: Double = 0
    @Published private(set) var ambience: Double = 0
    @Published private(set) var surround: Double = 0
    @Published private(set) var reverb: Double = 0
    @Published private(set) var outputGainDB: Double = 0
    @Published private(set) var balance: Double = 0

    private let lock = NSLock()
    private var stored = Snapshot()
    private var storedRevision = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored.enabled = defaults.bool(forKey: "ManyuMusic.fxEnabled")
        stored.lowBoost = defaults.double(forKey: "ManyuMusic.fxLowBoost")
        stored.bassEnhance = defaults.double(forKey: "ManyuMusic.fxBassEnhance")
        stored.warmth = defaults.double(forKey: "ManyuMusic.fxWarmth")
        stored.vocalEnhance = defaults.double(forKey: "ManyuMusic.fxVocalEnhance")
        stored.presence = defaults.double(forKey: "ManyuMusic.fxPresence")
        stored.clarity = defaults.double(forKey: "ManyuMusic.fxClarity")
        stored.trebleBoost = defaults.double(forKey: "ManyuMusic.fxTrebleBoost")
        stored.dynamics = defaults.double(forKey: "ManyuMusic.fxDynamics")
        stored.ambience = defaults.double(forKey: "ManyuMusic.fxAmbience")
        stored.surround = defaults.double(forKey: "ManyuMusic.fxSurround")
        stored.reverb = defaults.double(forKey: "ManyuMusic.fxReverb")
        stored.outputGainDB = defaults.double(forKey: "ManyuMusic.fxOutputGain")
        stored.balance = defaults.double(forKey: "ManyuMusic.fxBalance")
        mirrorToPublished()
    }

    private func mirrorToPublished() {
        enabled = stored.enabled
        lowBoost = stored.lowBoost
        bassEnhance = stored.bassEnhance
        warmth = stored.warmth
        vocalEnhance = stored.vocalEnhance
        presence = stored.presence
        clarity = stored.clarity
        trebleBoost = stored.trebleBoost
        dynamics = stored.dynamics
        ambience = stored.ambience
        surround = stored.surround
        reverb = stored.reverb
        outputGainDB = stored.outputGainDB
        balance = stored.balance
    }

    // MARK: 音频线程读取

    var revision: Int {
        lock.lock(); defer { lock.unlock() }
        return storedRevision
    }

    var isBypassed: Bool {
        lock.lock(); defer { lock.unlock() }
        return !stored.enabled
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    // MARK: 写入（UI 线程）

    func setEnabled(_ value: Bool) {
        lock.lock()
        stored.enabled = value
        storedRevision += 1
        lock.unlock()
        enabled = value
        defaults.set(value, forKey: "ManyuMusic.fxEnabled")
    }

    private func setPercent(
        _ value: Double,
        keyPath: WritableKeyPath<Snapshot, Double>,
        published: ReferenceWritableKeyPath<AudioEnhancer, Double>,
        defaultsKey: String
    ) {
        let clamped = min(max(value, Self.percentRange.lowerBound), Self.percentRange.upperBound)
        lock.lock()
        stored[keyPath: keyPath] = clamped
        storedRevision += 1
        lock.unlock()
        self[keyPath: published] = clamped
        defaults.set(clamped, forKey: defaultsKey)
    }

    func setLowBoost(_ value: Double) {
        setPercent(value, keyPath: \.lowBoost, published: \.lowBoost, defaultsKey: "ManyuMusic.fxLowBoost")
    }

    func setBassEnhance(_ value: Double) {
        setPercent(value, keyPath: \.bassEnhance, published: \.bassEnhance, defaultsKey: "ManyuMusic.fxBassEnhance")
    }

    func setWarmth(_ value: Double) {
        setPercent(value, keyPath: \.warmth, published: \.warmth, defaultsKey: "ManyuMusic.fxWarmth")
    }

    func setVocalEnhance(_ value: Double) {
        setPercent(value, keyPath: \.vocalEnhance, published: \.vocalEnhance, defaultsKey: "ManyuMusic.fxVocalEnhance")
    }

    func setPresence(_ value: Double) {
        setPercent(value, keyPath: \.presence, published: \.presence, defaultsKey: "ManyuMusic.fxPresence")
    }

    func setClarity(_ value: Double) {
        setPercent(value, keyPath: \.clarity, published: \.clarity, defaultsKey: "ManyuMusic.fxClarity")
    }

    func setTrebleBoost(_ value: Double) {
        setPercent(value, keyPath: \.trebleBoost, published: \.trebleBoost, defaultsKey: "ManyuMusic.fxTrebleBoost")
    }

    func setDynamics(_ value: Double) {
        setPercent(value, keyPath: \.dynamics, published: \.dynamics, defaultsKey: "ManyuMusic.fxDynamics")
    }

    func setAmbience(_ value: Double) {
        setPercent(value, keyPath: \.ambience, published: \.ambience, defaultsKey: "ManyuMusic.fxAmbience")
    }

    func setSurround(_ value: Double) {
        setPercent(value, keyPath: \.surround, published: \.surround, defaultsKey: "ManyuMusic.fxSurround")
    }

    func setReverb(_ value: Double) {
        setPercent(value, keyPath: \.reverb, published: \.reverb, defaultsKey: "ManyuMusic.fxReverb")
    }

    func setOutputGain(_ value: Double) {
        let clamped = min(max(value, Self.outputGainRange.lowerBound), Self.outputGainRange.upperBound)
        lock.lock()
        stored.outputGainDB = clamped
        storedRevision += 1
        lock.unlock()
        outputGainDB = clamped
        defaults.set(clamped, forKey: "ManyuMusic.fxOutputGain")
    }

    func setBalance(_ value: Double) {
        let clamped = min(max(value, Self.balanceRange.lowerBound), Self.balanceRange.upperBound)
        lock.lock()
        stored.balance = clamped
        storedRevision += 1
        lock.unlock()
        balance = clamped
        defaults.set(clamped, forKey: "ManyuMusic.fxBalance")
    }

    /// 全部恢复默认（开关保持当前状态）。
    func resetAll() {
        let keepEnabled = enabled
        lock.lock()
        stored = Snapshot()
        stored.enabled = keepEnabled
        storedRevision += 1
        lock.unlock()
        mirrorToPublished()
        for key in [
            "ManyuMusic.fxLowBoost", "ManyuMusic.fxBassEnhance", "ManyuMusic.fxWarmth",
            "ManyuMusic.fxVocalEnhance", "ManyuMusic.fxPresence", "ManyuMusic.fxClarity",
            "ManyuMusic.fxTrebleBoost", "ManyuMusic.fxDynamics", "ManyuMusic.fxAmbience",
            "ManyuMusic.fxSurround", "ManyuMusic.fxReverb", "ManyuMusic.fxOutputGain",
            "ManyuMusic.fxBalance",
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - 实时 DSP 引擎（每个 tap 一份状态）

/// 音效增强实时处理：在 EQ 级联之后执行。
/// 处理顺序：7 段滤波 → 动态压缩 → 早反射(环境感) → 混响(环境混响)
/// → M/S 立体声扩展(环绕声) → 声道平衡 + 输出增益 → 限幅。
/// 所有缓冲在 prepare 时按采样率一次性分配，音频线程内无内存分配。
final class EnhancerEngine {
    private let enhancer: AudioEnhancer
    var sampleRate: Double = 48_000
    var channels = 2

    /// 滤波段延迟状态 [声道][段]（转置直接 II 型 s1/s2）。
    private var fxStates: [[(s1: Float, s2: Float)]] = []
    /// 缓存的 7 段 Float 系数，与 enhancer.revision 对齐。
    private var fxCoeffs: [[Float]] = []
    private var fxCachedRevision = -1

    // 压缩器状态（立体声耦合侧链）
    private var compEnv: Float = 0
    private var compGain: Float = 1

    // 早反射（环境感）：单声道 send 环形缓冲
    private var erBuffer: [Float] = []
    private var erIndex = 0
    private var erTaps: [(offset: Int, gainL: Float, gainR: Float)] = []
    private var erSmooth: Float = 0

    // 混响（环境混响）：4 comb（L 取前 2、R 取后 2 去相关）+ 每声道 2 allpass
    private var combBuffers: [[Float]] = []
    private var combIndices: [Int] = []
    private var apBuffersL: [[Float]] = []
    private var apBuffersR: [[Float]] = []
    private var apIndexL = [0, 0]
    private var apIndexR = [0, 0]
    private var wetSmooth: Float = 0

    /// 帧级常量（process 开头计算一次）。
    struct FrameContext {
        var gain: Float = 1
        var gainL: Float = 1
        var gainR: Float = 1
        var dynamics: Float = 0
        var ambience: Float = 0
        var surround: Float = 0
        var reverb: Float = 0
        var threshold: Float = 0
        var attackCoef: Float = 0
        var releaseCoef: Float = 0
        var makeup: Float = 1
    }
    private var frame = FrameContext()

    init(enhancer: AudioEnhancer) {
        self.enhancer = enhancer
    }

    /// prepare 回调：按采样率/声道数重建缓冲与状态。
    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = max(1, channels)
        let sr = sampleRate
        let ratio = sr / 44_100.0

        // 早反射缓冲 20ms，L/R 错开的 taps（ms, 增益）
        erBuffer = .init(repeating: 0, count: max(64, Int(0.020 * sr)))
        erIndex = 0
        erTaps = [
            (Int(0.0070 * sr), 0.42, 0.18),
            (Int(0.0110 * sr), 0.30, 0.40),
            (Int(0.0150 * sr), 0.20, 0.26),
            (Int(0.0183 * sr), 0.12, 0.32),
        ].map { tap in
            (offset: min(tap.0, erBuffer.count - 1), gainL: tap.1, gainR: tap.2)
        }
        erSmooth = 0

        // Schroeder 混响：4 comb（freeverb 经典长度按采样率缩放）
        let combTunings = [1_116, 1_188, 1_277, 1_356].map {
            max(32, Int(Double($0) * ratio))
        }
        combBuffers = combTunings.map { .init(repeating: 0, count: $0) }
        combIndices = .init(repeating: 0, count: combTunings.count)
        // 每声道 2 个 allpass（L/R 错开实现去相关）
        let apL = [556, 441].map { max(8, Int(Double($0) * ratio)) }
        let apR = [509, 397].map { max(8, Int(Double($0) * ratio)) }
        apBuffersL = apL.map { .init(repeating: 0, count: $0) }
        apBuffersR = apR.map { .init(repeating: 0, count: $0) }
        apIndexL = [0, 0]
        apIndexR = [0, 0]
        wetSmooth = 0

        compEnv = 0
        compGain = 1
        fxStates = (0..<self.channels).map { _ in
            (0..<7).map { _ in (s1: 0 as Float, s2: 0 as Float) }
        }
        fxCachedRevision = -1  // 强制重建系数
    }

    /// 参数变化时重建 7 段滤波系数（音频线程一次性，代价 7 段三角函数）。
    private func refreshFxCoefficientsIfNeeded(_ snap: AudioEnhancer.Snapshot) {
        let rev = enhancer.revision
        guard rev != fxCachedRevision else { return }
        let sr = sampleRate
        func gain(_ percent: Double, maxDB: Double) -> Double { percent / 100 * maxDB }
        let sections: [Equalizer.Section] = [
            snap.lowBoost > 0.01
                ? Equalizer.lowShelf(f0: 60, sampleRate: sr, gainDB: gain(snap.lowBoost, maxDB: 8))
                : .identity,
            snap.bassEnhance > 0.01
                ? Equalizer.peaking(f0: 100, sampleRate: sr, gainDB: gain(snap.bassEnhance, maxDB: 6), q: 0.9)
                : .identity,
            snap.warmth > 0.01
                ? Equalizer.peaking(f0: 250, sampleRate: sr, gainDB: gain(snap.warmth, maxDB: 4), q: 0.8)
                : .identity,
            snap.vocalEnhance > 0.01
                ? Equalizer.peaking(f0: 3_000, sampleRate: sr, gainDB: gain(snap.vocalEnhance, maxDB: 5), q: 1.0)
                : .identity,
            snap.presence > 0.01
                ? Equalizer.peaking(f0: 4_000, sampleRate: sr, gainDB: gain(snap.presence, maxDB: 4), q: 1.1)
                : .identity,
            snap.clarity > 0.01
                ? Equalizer.peaking(f0: 8_000, sampleRate: sr, gainDB: gain(snap.clarity, maxDB: 4), q: 1.0)
                : .identity,
            snap.trebleBoost > 0.01
                ? Equalizer.highShelf(f0: 8_000, sampleRate: sr, gainDB: gain(snap.trebleBoost, maxDB: 8))
                : .identity,
        ]
        fxCoeffs = sections.map { [$0.b0, $0.b1, $0.b2, $0.a1, $0.a2].map(Float.init) }
        fxCachedRevision = rev
        // 参数变化后滤波状态清零，避免旧信号残留
        fxStates = (0..<channels).map { _ in
            (0..<fxCoeffs.count).map { _ in (s1: 0 as Float, s2: 0 as Float) }
        }
    }

    /// 就地处理整个 AudioBufferList（非交织与交织布局，与 EQTap 相同约定）。
    func process(_ pointer: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0 else { return }
        let snap = enhancer.snapshot()
        guard snap.enabled else { return }
        refreshFxCoefficientsIfNeeded(snap)

        var context = FrameContext()
        context.gain = Float(pow(10, snap.outputGainDB / 20))
        context.gainL = Float(1 - max(0, snap.balance))
        context.gainR = Float(1 - max(0, -snap.balance))
        context.dynamics = Float(snap.dynamics / 100)
        context.ambience = Float(snap.ambience / 100)
        context.surround = Float(snap.surround / 100)
        context.reverb = Float(snap.reverb / 100)
        let sr = sampleRate
        if context.dynamics > 0.005 {
            // 阈值 -14dB → -28dB 随强度降低；attack 5ms / release 150ms
            let thresholdDB = -14 - Double(context.dynamics) * 14
            context.threshold = Float(pow(10, thresholdDB / 20))
            context.attackCoef = Float(exp(-1 / (0.005 * sr)))
            context.releaseCoef = Float(exp(-1 / (0.150 * sr)))
            context.makeup = 1 + context.dynamics * 0.4
        }
        frame = context

        let list = UnsafeMutableAudioBufferListPointer(pointer)
        if list.count > 1 {
            // 非交织：处理前两个声道，其余声道原样
            guard let dataL = list[0].mData, let dataR = list[1].mData else { return }
            let countL = Int(list[0].mDataByteSize) / MemoryLayout<Float>.size
            let countR = Int(list[1].mDataByteSize) / MemoryLayout<Float>.size
            let samplesL = dataL.bindMemory(to: Float.self, capacity: countL)
            let samplesR = dataR.bindMemory(to: Float.self, capacity: countR)
            let n = min(frames, countL, countR)
            for index in 0..<n {
                let out = processSamples(l: samplesL[index], r: samplesR[index])
                samplesL[index] = out.l
                samplesR[index] = out.r
            }
        } else if list.count == 1, let mData = list[0].mData {
            // 交织：帧步长为声道数
            let channelCount = max(1, Int(list[0].mNumberChannels))
            let total = Int(list[0].mDataByteSize) / MemoryLayout<Float>.size
            let samples = mData.bindMemory(to: Float.self, capacity: total)
            let usable = min(total / channelCount, frames)
            if channelCount == 1 {
                for index in 0..<usable {
                    let out = processSamples(l: samples[index], r: samples[index])
                    samples[index] = (out.l + out.r) * 0.5
                }
            } else {
                for index in 0..<usable {
                    let base = index * channelCount
                    let out = processSamples(l: samples[base], r: samples[base + 1])
                    samples[base] = out.l
                    samples[base + 1] = out.r
                }
            }
        }
    }

    /// 单帧立体声处理核心（internal 便于单元测试）。
    func processSamples(l inputL: Float, r inputR: Float) -> (l: Float, r: Float) {
        var l = inputL
        var r = inputR

        // 1. 7 段滤波
        l = fxCascade(l, channel: 0)
        r = fxCascade(r, channel: min(1, channels - 1))

        // 2. 动态增强（压缩动态范围，立体声耦合侧链）
        if frame.dynamics > 0.005 {
            let level = max(abs(l), abs(r))
            compEnv = max(level, compEnv * frame.releaseCoef)
            let target: Float = compEnv > frame.threshold ? frame.threshold / compEnv : 1
            let coef = target < compGain ? frame.attackCoef : frame.releaseCoef
            compGain += (target - compGain) * coef
            let gain = compGain * frame.makeup
            l *= gain
            r *= gain
        }

        // 3. 环境感：早反射（单声道 send，L/R 错开 taps）
        if frame.ambience > 0.005 {
            let target = frame.ambience * 0.35
            erSmooth += (target - erSmooth) * 0.0016
            if !erBuffer.isEmpty {
                let send = (l + r) * 0.5
                erBuffer[erIndex] = send
                let readIndex = erIndex
                erIndex = (erIndex + 1) % erBuffer.count
                var wetL: Float = 0
                var wetR: Float = 0
                let count = erBuffer.count
                for tap in erTaps {
                    let position = (readIndex - tap.offset + count) % count
                    wetL += erBuffer[position] * tap.gainL
                    wetR += erBuffer[position] * tap.gainR
                }
                l += wetL * erSmooth
                r += wetR * erSmooth
            }
        } else if erSmooth > 0.00001 {
            erSmooth *= 0.9995
        }

        // 4. 环境混响：Schroeder comb + allpass
        if frame.reverb > 0.005 {
            let target = frame.reverb * 0.42
            wetSmooth += (target - wetSmooth) * 0.0012
            let send = (l + r) * 0.5 * 0.12
            let (wetL, wetR) = reverbTail(send)
            l += wetL * wetSmooth
            r += wetR * wetSmooth
        } else if wetSmooth > 0.00001 {
            wetSmooth *= 0.9995
        }

        // 5. 环绕声：M/S 立体声扩展
        if frame.surround > 0.005 && channels > 1 {
            let mid = (l + r) * 0.5
            let side = (l - r) * 0.5 * (1 + frame.surround * 0.6)
            l = mid + side
            r = mid - side
        }

        // 6. 声道平衡 + 输出增益 + 限幅
        l = min(1, max(-1, l * frame.gainL * frame.gain))
        r = min(1, max(-1, r * frame.gainR * frame.gain))
        return (l, r)
    }

    /// 7 段滤波级联（转置直接 II 型）。
    @inline(__always)
    private func fxCascade(_ input: Float, channel: Int) -> Float {
        var x = input
        for s in 0..<fxCoeffs.count {
            let c = fxCoeffs[s]
            var d = fxStates[channel][s]
            let y = c[0] * x + d.s1
            d.s1 = c[1] * x - c[3] * y + d.s2
            d.s2 = c[2] * x - c[4] * y
            fxStates[channel][s] = d
            x = y
        }
        return x
    }

    /// 混响尾：4 comb（前 2 → L、后 2 → R 去相关）+ 每声道 2 allpass。
    @inline(__always)
    private func reverbTail(_ send: Float) -> (Float, Float) {
        var sumL: Float = 0
        var sumR: Float = 0
        for c in 0..<combBuffers.count {
            let index = combIndices[c]
            let delayed = combBuffers[c][index]
            combBuffers[c][index] = send + delayed * 0.78
            combIndices[c] = (index + 1) % combBuffers[c].count
            if c < 2 {
                sumL += delayed
            } else {
                sumR += delayed
            }
        }
        var outL = sumL * 0.24
        var outR = sumR * 0.24
        for a in 0..<2 {
            outL = allpassSample(outL, buffer: &apBuffersL[a], index: &apIndexL[a])
            outR = allpassSample(outR, buffer: &apBuffersR[a], index: &apIndexR[a])
        }
        return (outL, outR)
    }

    /// Schroeder allpass：y = -g·x + v，v' = x + g·v。
    @inline(__always)
    private func allpassSample(_ x: Float, buffer: inout [Float], index: inout Int) -> Float {
        guard !buffer.isEmpty else { return x }
        let g: Float = 0.5
        let delayed = buffer[index]
        let output = delayed - g * x
        buffer[index] = x + g * delayed
        index = (index + 1) % buffer.count
        return output
    }
}
