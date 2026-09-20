import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import MediaToolbox

// MARK: - 均衡器参数模型（线程安全）

/// 三十一段图形均衡器：20Hz ~ 20kHz（ISO 三分之一倍频程），
/// 各段增益 -6 ~ +6 dB（0.5 步进），每段 Q 值 0.1 ~ 18 独立可调（默认 1.4）。
/// 参数由 UI 线程写入、音频 tap 的实时线程读取，内部用锁保护；
/// revision 号让 tap 检测到参数变化后在下一帧前重建 biquad 系数。
/// tap 常驻播放条目（EQ 关闭时直通），同一份参数还喂给实时频谱。
/// 内置预设（参考 MoeKoe EQ）+ 自定义命名预设（UserDefaults JSON 持久化）。
final class Equalizer {
    /// ISO 1/3 倍频程中心频率（Hz）。
    static let bandFrequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1_000, 1_250, 1_600,
        2_000, 2_500, 3_150, 4_000, 5_000, 6_300, 8_000, 10_000, 12_500, 16_000,
        20_000,
    ]
    static let bandLabels: [String] = [
        "20", "25", "31.5", "40", "50", "63", "80", "100", "125", "160",
        "200", "250", "315", "400", "500", "630", "800", "1k", "1.25k", "1.6k",
        "2k", "2.5k", "3.15k", "4k", "5k", "6.3k", "8k", "10k", "12.5k", "16k",
        "20k",
    ]
    static let bandCount = 31
    static let gainRange: ClosedRange<Double> = -6...6
    static let gainStep = 0.5
    static let qRange: ClosedRange<Double> = 0.1...18
    static let qStep = 0.1
    static let defaultQ = 1.4

    struct Preset: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var gains: [Double]
    }

    /// 手动微调（不属于任何预设）时的虚拟预设 ID。
    static let customCurveID = "custom"

    static let flat = Preset(id: "flat", name: "平坦", gains: .init(repeating: 0, count: bandCount))

    /// 内置预设曲线（顺序与参考项目 MoeKoe EQ 的面板一致）。
    static let builtInPresets: [Preset] = [
        flat,
        Preset(id: "rock", name: "摇滚", gains: [
            3, 3, 2, 2, 1, 0, -1, -1, 0, 1, 2, 3, 4, 4, 3, 2, 1, 0, 0, 1,
            2, 3, 4, 4, 3, 2, 1, 0, -1, -1, 0,
        ]),
        Preset(id: "classical", name: "古典", gains: [
            4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 1, 2, 3, 4, 4, 4,
        ]),
        Preset(id: "pop", name: "流行", gains: [
            -1, 0, 0, 1, 2, 3, 4, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            1, 2, 3, 3, 2, 1, 0, 0, -1, -1, -1,
        ]),
        Preset(id: "jazz", name: "爵士", gains: [
            2, 2, 1, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 2, 1, 0, 0, 0, 0, 0,
            0, 0, 1, 2, 3, 3, 2, 1, 0, 0, 0,
        ]),
        Preset(id: "bass", name: "低音增强", gains: [
            4, 4, 3, 3, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]),
        Preset(id: "treble", name: "高音增强", gains: [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 1, 2, 3, 4, 4, 4, 4,
        ]),
        Preset(id: "vocal", name: "人声", gains: [
            -2, -1, 0, 0, 1, 2, 3, 4, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, -1, -2, -2, -2,
        ]),
        Preset(id: "fengxue", name: "仿：风雪调音", gains: [
            3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 1, 0, -1,
            1, 0, 0, 1, -2, 0, -1, -1, 1, 2, 1,
        ]),
        Preset(id: "ultimate", name: "极致听感", gains: [
            2, 2, 2, 2, 3, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, -1,
            -1, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        ]),
        Preset(id: "harmankardon", name: "醇美空间", gains: [
            2, 2, 3, 3, 3, 3, 2, 2, 1, 1, 0, 0, -1, -1, -1, 0, 0, 1, 1, 2,
            2, 2, 3, 3, 2, 1, 1, 1, 1, 1, 1,
        ]),
        Preset(id: "harmanTarget", name: "哈基米曲线", gains: [
            4, 4, 3, 3, 2, 2, 1, 1, 0, 0, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0,
            0, 0, 1, 1, 2, 2, 3, 4, 4, 5, 5,
        ]),
        Preset(id: "studioReference", name: "母带处理", gains: [
            2, 2, 1, 1, 0, 0, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2,
            2, 2, 1, 1, 0, 0, 0, 1, 2, 2, 2,
        ]),
        Preset(id: "vinylWarmth", name: "黑胶温暖", gains: [
            3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, -1, -2, -2, -3, -3, -4, -4,
        ]),
        Preset(id: "hiResDetail", name: "Hi-Res解析", gains: [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2,
            2, 2, 2, 3, 3, 2, 2, 3, 3, 3, 3,
        ]),
        Preset(id: "liveConcert", name: "演唱会近场", gains: [
            2.5, 2.5, 2, 2, 1.5, 1, 0.5, 0, -0.5, -0.5, -1, -0.5, 0, 0, 0.5, 1, 1.5, 2, 2.5, 3,
            3.5, 4, 3.5, 3, 2.5, 2, 2, 1.5, 1.5, 1, 1,
        ]),
        Preset(id: "immersivePanorama", name: "沉浸全景", gains: [
            3, 3, 2.5, 2, 2, 1.5, 1, 0.5, 0, -0.5, -1, -1, -0.5, 0, 0, 0.5, 1, 1.5, 1.5, 1,
            0.5, 0.5, 1, 1.5, 2, 2.5, 3, 3, 2.5, 2.5, 2,
        ]),
        Preset(id: "masterMonitor", name: "大师监听", gains: [
            3, 3, 2.5, 2, 1.5, 1, 0.5, 0, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, 0, 0, 0.5, 0.5, 0.5,
            1, 1.5, 2, 2.5, 2, 2.5, 3, 3.5, 4, 4.5, 4.5,
        ]),
        Preset(id: "edm", name: "电子舞曲", gains: [
            5, 5, 4, 4, 3, 2, 0, -1, -2, -2, -1, 0, -1, -2, -2, -1, 0, 0, 0, 1,
            2, 3, 4, 5, 5, 4, 3, 4, 5, 5, 4,
        ]),
        Preset(id: "hiphop", name: "嘻哈说唱", gains: [
            5, 5, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 2,
            1, 0, 0, 0, 0, 0, 0, 0, -1, -1, -1,
        ]),
        Preset(id: "acousticFolk", name: "民谣原声", gains: [
            -1, -1, 0, 0, 1, 1, 2, 2, 3, 3, 2, 1, 0, 0, 0, 0, 1, 2, 2, 2,
            1, 0, 0, 0, -1, -1, -1, -2, -2, -2, -2,
        ]),
        Preset(id: "podcast", name: "播客有声书", gains: [
            -5, -5, -4, -4, -3, -2, -1, 0, 0, 0, 1, 2, 3, 3, 2, 1, 0, 0, 0, 0,
            0, 0, -1, -1, -2, -2, -2, -2, -2, -2, -2,
        ]),
        Preset(id: "cinema", name: "影院模式", gains: [
            4, 5, 5, 4, 3, 2, 1, 0, -1, -1, 0, 0, 0, 0, 1, 2, 3, 3, 2, 1,
            0, 0, 1, 2, 2, 1, 0, 0, 1, 2, 2,
        ]),
        Preset(id: "lofiChill", name: "Lo-Fi休闲", gains: [
            2, 2, 3, 3, 3, 2, 2, 3, 3, 3, 2, 1, 0, 0, 0, 0, 0, -1, -1, -2,
            -2, -3, -3, -3, -4, -4, -4, -5, -5, -5, -5,
        ]),
        Preset(id: "metal", name: "金属硬核", gains: [
            3, 3, 2, 1, 0, -1, -2, -3, -3, -2, -1, 0, 1, 2, 3, 4, 5, 5, 4, 3,
            3, 4, 5, 5, 4, 3, 3, 4, 4, 3, 2,
        ]),
        Preset(id: "asmrSleep", name: "ASMR助眠", gains: [
            2, 2, 2, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, -1, -1, -2, -2,
            -3, -3, -3, -3, -4, -4, -4, -4, -4, -4, -4,
        ]),
        Preset(id: "workout", name: "运动", gains: [
            5, 5, 5, 4, 3, 2, 1, 0, 0, 1, 2, 2, 1, 0, 0, 1, 2, 3, 3, 3,
            4, 4, 4, 3, 3, 2, 2, 3, 4, 4, 3,
        ]),
        Preset(id: "pianoClassical", name: "古典钢琴", gains: [
            -1, 0, 1, 2, 3, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3,
            3, 3, 2, 2, 1, 0, 0, -1, -2, -2, -2,
        ]),
        Preset(id: "deepBass", name: "澎湃重低音", gains: [
            2, 2, 3, 4, 5, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]),
        Preset(id: "transparentFull", name: "通透饱满", gains: [
            2, 3, 3, 4, 4, 5, 4, 3, 1, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 4,
            4, 4, 4, 4, 3, 3, 2, 1, 1, 1, 1,
        ]),
        Preset(id: "mainstreamPop", name: "华语流行", gains: [
            1, 2, 2, 3, 4, 4, 4, 3, 1, 0, 0, 0, 0, 0, 0, 1, 3, 4, 4, 3,
            2, 1, 0, 1, 2, 2, 1, 0, 0, 0, 0,
        ]),
        Preset(id: "westernPop", name: "欧美流行", gains: [
            3, 4, 4, 4, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 3,
            3, 3, 4, 4, 3, 2, 1, 0, 0, 0, 0,
        ]),
        Preset(id: "rnbSoul", name: "R&B律动", gains: [
            3, 3, 4, 4, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3,
            2, 1, 0, 0, 0, 0, -1, -1, -1, -1, -1,
        ]),
        Preset(id: "vastSoundstage", name: "声场", gains: [
            1, 1, 1, 2, 2, 2, 1, 1, 0, 0, -1, -1, -1, -1, 0, 0, 0, 0, 1, 1,
            2, 2, 3, 3, 4, 4, 4, 3, 2, 2, 1,
        ]),
        Preset(id: "sweetVocal", name: "派大星", gains: [
            -5, -5, -4, -4, -3, -2, 0, 1, 2, 3, 3, 3, 2, 1, 0, 0, 0, 0, 0, 0,
            0, 0, 0, -1, -1, -2, -2, -2, -3, -3, -3,
        ]),
    ]

    /// 旧版十段均衡器的频率表（迁移用）。
    private static let legacyBandFrequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    // UserDefaults 键
    static let enabledKey = "ManyuMusic.eqEnabled"
    static let selectedPresetIDKey = "ManyuMusic.eqSelectedPresetID"
    static let customPresetsKey = "ManyuMusic.eqCustomPresets"
    private static let gainsKey = "ManyuMusic.eqGains"
    private static let qValuesKey = "ManyuMusic.eqQValues"

    /// 实时频谱的共享采样环形缓冲（所有 tap 的下混采样都写进来）。
    let spectrumRing = EQSpectrumRing()
    /// 音效增强（与本 EQ 共用同一个音频 tap，EQ 处理后级联，开关互相独立）。
    let enhancer: AudioEnhancer

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var storedGains: [Double]
    private var storedQValues: [Double]
    private var storedRevision = 0
    /// isEnabled 的锁内镜像：音频线程每帧读 bypass 状态不再碰 UserDefaults。
    private var storedEnabled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enhancer = AudioEnhancer(defaults: defaults)
        let saved = defaults.array(forKey: Self.gainsKey) as? [Double]
        let curve: [Double]
        switch saved?.count {
        case Self.bandCount:
            curve = saved!
        case Self.legacyBandFrequencies.count:
            // 旧版十段曲线 → 在对数频率轴上插值到 31 段。
            curve = Self.interpolatedGains(from: saved!, oldFrequencies: Self.legacyBandFrequencies)
        default:
            curve = Self.flat.gains
        }
        self.storedGains = curve.map {
            min(max($0, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        }

        let savedQ = defaults.array(forKey: Self.qValuesKey) as? [Double]
        self.storedQValues = (savedQ?.count == Self.bandCount)
            ? savedQ!.map { min(max($0, Self.qRange.lowerBound), Self.qRange.upperBound) }
            : .init(repeating: Self.defaultQ, count: Self.bandCount)

        self.storedEnabled = isEnabled
        migrateCustomPresetsIfNeeded()
    }

    /// 把任意旧频率表上的曲线插值到当前 31 段（对数频率轴线性插值，端点钳制）。
    static func interpolatedGains(from oldGains: [Double], oldFrequencies: [Double]) -> [Double] {
        guard !oldGains.isEmpty, oldGains.count == oldFrequencies.count else {
            return .init(repeating: 0, count: bandCount)
        }
        let logFreqs = oldFrequencies.map { log2($0) }
        return bandFrequencies.map { frequency in
            let x = log2(frequency)
            if x <= logFreqs[0] { return oldGains[0] }
            if x >= logFreqs[logFreqs.count - 1] { return oldGains[oldGains.count - 1] }
            for index in 1..<logFreqs.count where logFreqs[index] >= x {
                let t = (x - logFreqs[index - 1]) / (logFreqs[index] - logFreqs[index - 1])
                return oldGains[index - 1] + t * (oldGains[index] - oldGains[index - 1])
            }
            return oldGains[oldGains.count - 1]
        }
    }

    /// 旧版十段自定义预设 → 插值为 31 段并回写；形状不对的预设直接丢弃。
    private func migrateCustomPresetsIfNeeded() {
        guard let data = defaults.data(forKey: Self.customPresetsKey),
              var list = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        var changed = false
        list = list.compactMap { preset in
            if preset.gains.count == Self.bandCount { return preset }
            guard preset.gains.count == Self.legacyBandFrequencies.count else { return nil }
            changed = true
            var migrated = preset
            migrated.gains = Self.interpolatedGains(from: preset.gains, oldFrequencies: Self.legacyBandFrequencies)
            return migrated
        }
        guard changed else { return }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Self.customPresetsKey)
        }
    }

    // MARK: 开关 / 预设选择（与 gapless 等设置同款：读时兜底、写即持久化）

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            lock.lock()
            storedEnabled = newValue
            lock.unlock()
        }
    }

    /// 音频线程每帧读取：EQ 关闭时 tap 直通（仍喂频谱）。
    var isBypassed: Bool {
        lock.lock(); defer { lock.unlock() }
        return !storedEnabled
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

    /// 当前 31 段增益（dB）。音频 tap 通过 revision 感知变化。
    var gains: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storedGains
    }

    /// 当前 31 段 Q 值。
    var qValues: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storedQValues
    }

    var revision: Int {
        lock.lock(); defer { lock.unlock() }
        return storedRevision
    }

    func setGains(_ newGains: [Double]) {
        precondition(newGains.count == Self.bandCount, "EQ 曲线必须是 31 段")
        let clamped = newGains.map {
            min(max($0, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        }
        lock.lock()
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

    func setQValues(_ newQValues: [Double]) {
        precondition(newQValues.count == Self.bandCount, "EQ Q 值必须是 31 段")
        let clamped = newQValues.map {
            min(max($0, Self.qRange.lowerBound), Self.qRange.upperBound)
        }
        lock.lock()
        storedQValues = clamped
        storedRevision += 1
        lock.unlock()
        defaults.set(clamped, forKey: Self.qValuesKey)
    }

    func setQ(at index: Int, to value: Double) {
        var q = qValues
        q[index] = value
        setQValues(q)
    }

    /// 全部归零 + Q 恢复默认（「重置」按钮）。
    func resetAll() {
        setGains(Self.flat.gains)
        setQValues(.init(repeating: Self.defaultQ, count: Self.bandCount))
        selectedPresetID = Self.flat.id
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

    /// 峰值（peaking EQ）段，Q 为该段独立带宽参数。
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

    /// 依当前曲线设计 31 个 biquad 段：两端 shelf、中间 peaking（各段独立 Q）。
    func coefficients(sampleRate: Double) -> [Section] {
        let g = gains
        let q = qValues
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
                sections.append(Self.peaking(f0: frequency, sampleRate: sampleRate, gainDB: g[index], q: q[index]))
            }
        }
        return sections
    }
}

// MARK: - 每个 tap 独立的滤波状态与实时处理

/// tap 上下文：共享的 Equalizer 参数 + 本 tap 独立的各段延迟状态 + 频谱喂送。
/// prepare 回调确定采样率/声道数；process 回调在实时音频线程运行。
final class EQTapContext {
    let equalizer: Equalizer
    let spectrumRing: EQSpectrumRing?
    /// 音效增强实时引擎（EQ 之后级联，独立开关）。
    let enhancerEngine: EnhancerEngine
    var sampleRate: Double = 48_000
    var channels = 2
    /// [声道][段] 的二阶状态（转置直接 II 型的 s1/s2）。
    var delays: [[(s1: Float, s2: Float)]] = []
    /// 缓存的 Float 系数 [段][b0,b1,b2,a1,a2]，与 equalizer.revision 对齐。
    var coeffs: [[Float]] = []
    var cachedRevision = -1
    /// 频谱下混暂存（prepare 时按 maxFrames 一次性分配，音频线程不再分配内存）。
    var monoScratch: [Float] = []

    init(equalizer: Equalizer, spectrumRing: EQSpectrumRing?) {
        self.equalizer = equalizer
        self.spectrumRing = spectrumRing
        self.enhancerEngine = EnhancerEngine(enhancer: equalizer.enhancer)
    }

    func resetForPrepare(sampleRate: Double, channels: Int, maxFrames: Int) {
        self.sampleRate = sampleRate
        self.channels = max(1, channels)
        monoScratch = .init(repeating: 0, count: max(1, maxFrames))
        if let spectrumRing {
            spectrumRing.sampleRate = sampleRate
        }
        rebuildDelays()
        enhancerEngine.prepare(sampleRate: sampleRate, channels: self.channels)
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

    /// 参数变化时重建系数（在音频线程调用，代价仅 31 段三角函数，一次性）。
    private func refreshCoefficientsIfNeeded() {
        let rev = equalizer.revision
        guard rev != cachedRevision || coeffs.count != Equalizer.bandCount else { return }
        let sections = equalizer.coefficients(sampleRate: sampleRate)
        coeffs = sections.map { [$0.b0, $0.b1, $0.b2, $0.a1, $0.a2].map(Float.init) }
        cachedRevision = rev
        rebuildDelays()  // 参数变化后从零状态开始，避免旧状态残留
    }

    /// 就地处理 AudioBufferList。支持非交织（每声道一个 buffer）与交织两种布局。
    /// EQ 关闭（bypass）时跳过滤波，但频谱喂送照常；随后音效增强按独立开关处理。
    func process(bufferList pointer: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        feedSpectrum(pointer, frames: frames)

        // EQ 滤波（关闭或平直曲线时直通）
        if !equalizer.isBypassed {
            refreshCoefficientsIfNeeded()
            let g = equalizer.gains
            if !g.allSatisfy({ abs($0) < 0.001 }) {
                applyCascade(pointer, frames: frames)
            }
        }

        // 音效增强（独立开关，与 EQ 状态无关；关闭时引擎内部直通）
        enhancerEngine.process(pointer, frames: frames)
    }

    /// EQ 31 段级联：非交织逐声道、交织按帧步进。
    private func applyCascade(_ pointer: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
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

    /// 下混为单声道写入频谱环形缓冲（EQ 开关无关，恒定喂送）。
    private func feedSpectrum(_ pointer: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard let spectrumRing, frames > 0 else { return }
        let count = min(frames, monoScratch.count)
        guard count > 0 else { return }
        let list = UnsafeMutableAudioBufferListPointer(pointer)
        var written = 0
        if list.count > 1 {
            // 非交织：逐帧平均前两个声道。
            let channelCount = min(list.count, 2)
            let buffers: [UnsafeMutablePointer<Float>?] = (0..<channelCount).map { channel in
                guard let mData = list[channel].mData else { return nil }
                return mData.bindMemory(to: Float.self, capacity: Int(list[channel].mDataByteSize) / MemoryLayout<Float>.size)
            }
            guard buffers.allSatisfy({ $0 != nil }) else { return }
            for frame in 0..<count {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += buffers[channel]![frame]
                }
                monoScratch[frame] = sum / Float(channelCount)
            }
            written = count
        } else if list.count == 1, let mData = list[0].mData {
            // 交织：帧步长为声道数。
            let channelCount = max(1, Int(list[0].mNumberChannels))
            let total = Int(list[0].mDataByteSize) / MemoryLayout<Float>.size
            let samples = mData.bindMemory(to: Float.self, capacity: total)
            let usable = min(count, total / channelCount)
            for frame in 0..<usable {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += samples[frame * channelCount + channel]
                }
                monoScratch[frame] = sum / Float(channelCount)
            }
            written = usable
        }
        if written > 0 {
            monoScratch.withUnsafeBufferPointer { buffer in
                spectrumRing.write(buffer.baseAddress!, count: written)
            }
        }
    }
}

// MARK: - MTAudioProcessingTap 胶水

/// 把 EQTapContext 挂进 AVPlayerItem 的音频管线：
/// AVMutableAudioMixInputParameters.audioTapProcessor。
/// tap 常驻（与 EQ 开关无关）：EQ 关闭时直通，频谱始终取流。
enum EQTap {
    /// 为新 item 挂 tap（异步取音轨，完成后设置 audioMix）。
    static func attach(to item: AVPlayerItem, equalizer: Equalizer) {
        item.asset.loadTracks(withMediaType: .audio) { tracks, _ in
            guard let track = tracks?.first else { return }
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
        let context = EQTapContext(equalizer: equalizer, spectrumRing: equalizer.spectrumRing)
        let contextPointer = Unmanaged
            .passRetained(context)
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
        channels: Int(format.mChannelsPerFrame),
        maxFrames: max(Int(maxFrames), 1)
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
