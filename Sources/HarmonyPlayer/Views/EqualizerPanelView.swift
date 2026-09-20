import SwiftUI

/// 均衡器面板（参考 MoeKoe EQ 面板设计）：
/// 完整模式（设置页）：头部 → 三页签（均衡器/音效增强/高级功能）
/// → 实时频谱 → 预设 chips → 31 段垂直滑杆（双击归零、每段 Q 值可调）。
/// 「音效增强」页签为完整实现：频率调节（8 项滤波/压缩）、空间效果（3 项）、输出控制（2 项）。
/// 精简模式（播放栏 EQ 弹窗，`showsCloseButton: true`）：仅头部 + 预设 chips。
struct EqualizerPanelView: View {
    @EnvironmentObject private var player: AudioPlayer
    @AppStorage(Equalizer.enabledKey) private var eqEnabled = false

    var showsCloseButton = false
    var onClose: () -> Void = {}

    @StateObject private var analyzer = EQSpectrumAnalyzer()

    // 本地镜像（Equalizer 非 Observable，滑块绑定镜像状态手动同步）
    @State private var gains: [Double] = .init(repeating: 0, count: Equalizer.bandCount)
    @State private var qValues: [Double] = .init(repeating: Equalizer.defaultQ, count: Equalizer.bandCount)
    @State private var presetID = Equalizer.flat.id
    @State private var selectedTab: EQPanelTab = .equalizer
    @State private var showSavePresetDialog = false
    @State private var newPresetName = ""

    var body: some View {
        Group {
            if showsCloseButton {
                compactPanel
            } else {
                fullPanel
            }
        }
        .onAppear {
            syncEQState()
            if !showsCloseButton {
                analyzer.connect(to: player.equalizer.spectrumRing)
            }
        }
        .alert("保存自定义预设", isPresented: $showSavePresetDialog) {
            TextField("预设名称", text: $newPresetName)
            Button("保存") {
                _ = player.equalizer.saveCustomPreset(named: newPresetName)
                syncEQState()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("以当前 31 段滑块的曲线保存，保存后可在预设区随时切换")
        }
    }

    // MARK: - 完整面板（设置页）

    private var fullPanel: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider().opacity(0.08)

            Group {
                switch selectedTab {
                case .equalizer:
                    equalizerTab
                case .enhancement:
                    AudioEnhancementPanel(enhancer: player.equalizer.enhancer)
                case .advanced:
                    placeholderTab(
                        icon: "slider.horizontal.2.square.on.square",
                        title: "高级功能",
                        message: "动态 EQ、限幅器、声道独立调节等高级处理将在后续版本提供"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 精简面板（播放栏弹窗）：仅头部 + 预设

    private var compactPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.08)
            VStack(alignment: .leading, spacing: 10) {
                Text("预设")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
                presetChips
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(width: 540)
    }

    // MARK: - 头部（标题 + 状态 + 关闭EQ / 重置 + 弹窗关闭钮）

    private var header: some View {
        HStack(spacing: 8) {
            Text("31段均衡器")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hpAccent)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(eqEnabled ? Color.green : Color.hpTextPrimary.opacity(0.3))
                    .frame(width: 7, height: 7)
                Text(eqEnabled ? "EQ运行中" : "EQ已关闭")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(eqEnabled ? Color.green : Color.hpTextPrimary.opacity(0.45))
            }

            Button {
                let newValue = !eqEnabled
                eqEnabled = newValue
                player.setEQEnabled(newValue)
            } label: {
                Text(eqEnabled ? "关闭EQ" : "开启EQ")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Color.hpTextPrimary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(eqEnabled ? "关闭均衡器" : "开启均衡器")

            Button {
                player.equalizer.resetAll()
                syncEQState()
            } label: {
                Text("重置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Color.red.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.red.opacity(0.35), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .help("全部归零并恢复默认 Q 值")

            if showsCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(
                            Color.hpTextPrimary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - 页签栏

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(EQPanelTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.hpAccent : Color.hpTextPrimary.opacity(0.55))
                        Capsule()
                            .fill(isSelected ? Color.hpAccent : .clear)
                            .frame(width: 26, height: 2.5)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // MARK: - 均衡器页签

    private var equalizerTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 频谱分析
            Text("频谱分析")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
            EQSpectrumView(analyzer: analyzer)
                .frame(height: 180)

            // 预设
            Text("预设")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
            presetChips

            // 均衡器调节
            HStack(spacing: 8) {
                Text("均衡器调节")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
                Text("双击滑杆归零 | Q值可调")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
            }
            slidersRow
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: 预设 chips（内置 + 自定义 + 保存/删除）

    private var presetChips: some View {
        let customPresets = player.equalizer.customPresets
        let selectedIsCustom = customPresets.contains { $0.id == presetID }
        return FlowLayout(spacing: 6) {
            ForEach(Equalizer.builtInPresets) { preset in
                EQPresetChip(
                    title: preset.name,
                    isSelected: presetID == preset.id
                ) {
                    player.equalizer.apply(preset: preset)
                    syncEQState()
                }
            }
            ForEach(customPresets) { preset in
                EQPresetChip(
                    title: preset.name,
                    isSelected: presetID == preset.id
                ) {
                    player.equalizer.apply(preset: preset)
                    syncEQState()
                }
            }
            EQPresetChip(title: "+ 保存预设", isSelected: false, tint: .green) {
                newPresetName = ""
                showSavePresetDialog = true
            }
            .help("把当前曲线保存为命名自定义预设")
            if selectedIsCustom {
                EQPresetChip(title: "删除预设", isSelected: false, tint: .red) {
                    player.equalizer.removeCustomPreset(id: presetID)
                    syncEQState()
                }
                .help("删除当前选中的自定义预设")
            }
        }
    }

    // MARK: 31 段垂直滑杆

    private var slidersRow: some View {
        HStack(spacing: 0) {
            ForEach(0..<Equalizer.bandCount, id: \.self) { index in
                EQBandColumn(
                    index: index,
                    gain: Binding(
                        get: { gains[index] },
                        set: { newValue in
                            gains[index] = newValue
                            player.equalizer.setGain(at: index, to: newValue)
                            if presetID != Equalizer.customCurveID {
                                presetID = Equalizer.customCurveID
                            }
                        }
                    ),
                    qValue: Binding(
                        get: { qValues[index] },
                        set: { newValue in
                            qValues[index] = newValue
                            player.equalizer.setQ(at: index, to: newValue)
                        }
                    )
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 把 Equalizer 里的真实状态同步到本地镜像（面板出现/预设切换后调用）。
    private func syncEQState() {
        gains = player.equalizer.gains
        qValues = player.equalizer.qValues
        presetID = player.equalizer.selectedPresetID
    }

    // MARK: 占位页签

    private func placeholderTab(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.22))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .padding(14)
    }
}

// MARK: - 音效增强面板

/// 音效增强页签：开关 + 重置 → 频率调节 8 卡 → 空间效果 3 卡 → 输出控制 2 卡。
/// 全部参数实时生效（音频 tap 内 DSP 处理）并自动持久化。
struct AudioEnhancementPanel: View {
    @ObservedObject var enhancer: AudioEnhancer

    private struct CardSpec {
        let title: String
        let subtitle: String
        let value: (AudioEnhancer) -> Double
        let apply: (AudioEnhancer, Double) -> Void
        let display: (Double) -> String
        var range: ClosedRange<Double> = AudioEnhancer.percentRange
        var defaultValue: Double = 0
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func balanceText(_ value: Double) -> String {
        if abs(value) < 0.005 { return "居中" }
        let percent = Int(abs(value) * 100)
        return value < 0 ? "左 \(percent)%" : "右 \(percent)%"
    }

    private static let frequencyCards: [CardSpec] = [
        CardSpec(title: "低频提升", subtitle: "增强60Hz低频", value: { $0.lowBoost }, apply: { $0.setLowBoost($1) }, display: percentText),
        CardSpec(title: "低音增强", subtitle: "增强低频力度", value: { $0.bassEnhance }, apply: { $0.setBassEnhance($1) }, display: percentText),
        CardSpec(title: "温暖感", subtitle: "增强中低频", value: { $0.warmth }, apply: { $0.setWarmth($1) }, display: percentText),
        CardSpec(title: "人声增强", subtitle: "增强3kHz人声", value: { $0.vocalEnhance }, apply: { $0.setVocalEnhance($1) }, display: percentText),
        CardSpec(title: "临场感", subtitle: "增强4kHz频段", value: { $0.presence }, apply: { $0.setPresence($1) }, display: percentText),
        CardSpec(title: "清晰度", subtitle: "增强高频细节", value: { $0.clarity }, apply: { $0.setClarity($1) }, display: percentText),
        CardSpec(title: "高频提升", subtitle: "增强8kHz以上", value: { $0.trebleBoost }, apply: { $0.setTrebleBoost($1) }, display: percentText),
        CardSpec(title: "动态增强", subtitle: "压缩动态范围", value: { $0.dynamics }, apply: { $0.setDynamics($1) }, display: percentText),
    ]

    private static let spaceCards: [CardSpec] = [
        CardSpec(title: "环境感", subtitle: "添加空间感", value: { $0.ambience }, apply: { $0.setAmbience($1) }, display: percentText),
        CardSpec(title: "环绕声", subtitle: "立体声扩展", value: { $0.surround }, apply: { $0.setSurround($1) }, display: percentText),
        CardSpec(title: "环境混响", subtitle: "沉浸混响效果", value: { $0.reverb }, apply: { $0.setReverb($1) }, display: percentText),
    ]

    private static let outputCards: [CardSpec] = [
        CardSpec(
            title: "输出增益", subtitle: "整体音量增益",
            value: { $0.outputGainDB }, apply: { $0.setOutputGain($1) },
            display: { String(format: "%+.0f dB", $0) },
            range: AudioEnhancer.outputGainRange
        ),
        CardSpec(
            title: "声道平衡", subtitle: "左右声道平衡",
            value: { $0.balance }, apply: { $0.setBalance($1) },
            display: balanceText,
            range: AudioEnhancer.balanceRange
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                toggleRow
                groupHeader(icon: "slider.horizontal.3", title: "频率调节")
                cardGrid(Self.frequencyCards)
                groupHeader(icon: "hifispeaker.2", title: "空间效果")
                cardGrid(Self.spaceCards)
                groupHeader(icon: "dial.min", title: "输出控制")
                cardGrid(Self.outputCards)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    private var toggleRow: some View {
        HStack(spacing: 10) {
            Toggle("音效增强", isOn: Binding(
                get: { enhancer.enabled },
                set: { enhancer.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 13, weight: .semibold))
            .help("开启或关闭音效增强")

            Spacer()

            Button {
                enhancer.resetAll()
            } label: {
                Text("重置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Color.red.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.red.opacity(0.35), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .help("音效增强全部参数恢复默认（开关保持不变）")
        }
    }

    private func groupHeader(icon: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
        }
    }

    private func cardGrid(_ specs: [CardSpec]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(0..<specs.count, id: \.self) { index in
                card(specs[index])
            }
        }
    }

    private func card(_ spec: CardSpec) -> some View {
        let value = spec.value(enhancer)
        let changed = abs(value - spec.defaultValue) > 0.004
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Text(spec.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(spec.display(value))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(changed ? Color.hpAccent : Color.hpTextPrimary.opacity(0.45))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { spec.value(enhancer) },
                    set: { spec.apply(enhancer, $0) }
                ),
                in: spec.range
            )
            .tint(Color.hpAccent)
            .controlSize(.small)
            Text(spec.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
        }
        .padding(11)
        .background(
            Color.hpTextPrimary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.hpTextPrimary.opacity(0.08), lineWidth: 0.6)
        )
    }
}

// MARK: - 页签定义

enum EQPanelTab: String, CaseIterable, Identifiable {
    case equalizer
    case enhancement
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equalizer: "均衡器"
        case .enhancement: "音效增强"
        case .advanced: "高级功能"
        }
    }
}

// MARK: - 实时频谱视图

/// 深色面板上的绿色实时频谱波浪（含下方渐变填充与频率刻度）：
/// 曲线用弱化张力的 Catmull-Rom 保留峰形，轮廓随真实频谱
/// 高低错落——像层叠的山峰而非均匀波浪；静默/暂停时衰减贴底。
/// 主线之下叠加一条更矮、衰减更慢的"远山影"（trailing）增加层次。
struct EQSpectrumView: View {
    @ObservedObject var analyzer: EQSpectrumAnalyzer

    private static let spectrumGreen = Color(red: 0.28, green: 0.82, blue: 0.42)

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.82))
            .overlay {
                Canvas { context, size in
                    let count = analyzer.levels.count
                    guard count > 1 else { return }

                    // 水平参考线（Y 轴五等分，划分更细）
                    for fraction in [0.2, 0.4, 0.6, 0.8] {
                        let y = size.height * fraction
                        var grid = Path()
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(
                            grid,
                            with: .color(.white.opacity(0.05)),
                            lineWidth: 0.5
                        )
                    }

                    // 主山峰线：真实频谱能量直接映射高度（无人工波浪叠加）
                    let mainPoints = (0..<count).map { index -> CGPoint in
                        let xNorm = Double(index) / Double(count - 1)
                        let value = max(analyzer.levels[index], 0.02)
                        return CGPoint(
                            x: size.width * CGFloat(xNorm),
                            y: size.height * (1 - CGFloat(value) * 0.95) - 2
                        )
                    }

                    // 远山影：矮化快照画在主线下方，峰过之后缓缓退去
                    let echoPoints = (0..<count).map { index -> CGPoint in
                        let xNorm = Double(index) / Double(count - 1)
                        let value = max(analyzer.trailing[index], 0.015)
                        return CGPoint(
                            x: size.width * CGFloat(xNorm),
                            y: size.height * (1 - CGFloat(value) * 0.95) - 2
                        )
                    }

                    // 远山影（仅描线，弱化显示）
                    let echoLine = Self.smoothPath(points: echoPoints)
                    context.stroke(
                        echoLine,
                        with: .color(Self.spectrumGreen.opacity(0.30)),
                        style: StrokeStyle(lineWidth: 1, lineJoin: .round)
                    )

                    // 主山峰曲线下方渐变填充
                    var fill = Self.smoothPath(points: mainPoints)
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()
                    context.fill(
                        fill,
                        with: .linearGradient(
                            Gradient(colors: [
                                Self.spectrumGreen.opacity(0.30),
                                Self.spectrumGreen.opacity(0.02),
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                    context.stroke(
                        Self.smoothPath(points: mainPoints),
                        with: .color(Self.spectrumGreen),
                        style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)
                    )
                }
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Text("20Hz")
                    Spacer()
                    Text("1k")
                    Spacer()
                    Text("20kHz")
                }
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onAppear { analyzer.start() }
            .onDisappear { analyzer.stop() }
    }

    /// Catmull-Rom → 三次贝塞尔：张力弱化（控制点系数 1/9），
    /// 保留峰谷的陡峭轮廓，只消除相邻点的细碎锯齿。
    private static func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : p2
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 9,
                y: p1.y + (p2.y - p0.y) / 9
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 9,
                y: p2.y - (p3.y - p1.y) / 9
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

// MARK: - 预设 chip

struct EQPresetChip: View {
    let title: String
    let isSelected: Bool
    var tint: Color?
    let action: () -> Void

    var body: some View {
        let highlight = tint ?? Color.hpAccent
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? highlight : Color.hpTextPrimary.opacity(0.72))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    (isSelected ? highlight.opacity(0.12) : Color.hpTextPrimary.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ? highlight.opacity(0.65) : Color.hpTextPrimary.opacity(0.10),
                            lineWidth: isSelected ? 1 : 0.6
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单个频段列（滑杆 + 增益 + Q + 频率标签）

struct EQBandColumn: View {
    let index: Int
    @Binding var gain: Double
    @Binding var qValue: Double

    @State private var showQEditor = false

    var body: some View {
        VStack(spacing: 3) {
            EQVerticalSlider(value: $gain, range: Equalizer.gainRange, step: Equalizer.gainStep)
                .frame(height: 128)

            Text(String(format: "%.1f", gain))
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(
                    abs(gain) > 0.01 ? Color.hpAccent : Color.hpTextPrimary.opacity(0.42)
                )
                .monospacedDigit()

            Button {
                showQEditor = true
            } label: {
                Text(String(format: "%.1f", qValue))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        Color.hpTextPrimary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help("频段 \(Equalizer.bandLabels[index]) 的 Q 值（点击调整）")
            .popover(isPresented: $showQEditor, arrowEdge: .bottom) {
                qEditor
            }

            Text(Equalizer.bandLabels[index])
                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
                .rotationEffect(.degrees(-45))
                .frame(width: 14, height: 26)
        }
    }

    /// Q 值编辑小弹窗：横向滑杆 0.1 ~ 18。
    private var qEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("频段 \(Equalizer.bandLabels[index]) Hz · Q 值")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                Slider(value: $qValue, in: Equalizer.qRange, step: Equalizer.qStep)
                    .frame(width: 190)
                Text(String(format: "%.1f", qValue))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            Text("Q 越小频段越宽、影响更平滑；越大频段越窄、调整更锐利")
                .font(.system(size: 9))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - 垂直滑杆（自绘，中心为 0 dB，双击归零）

struct EQVerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.5

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            ZStack {
                // 轨道
                Capsule()
                    .fill(Color.hpTextPrimary.opacity(0.16))
                    .frame(width: 2)
                // 0 dB 中线
                Rectangle()
                    .fill(Color.hpTextPrimary.opacity(0.12))
                    .frame(height: 1)
                // 滑块
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(
                        abs(value) < 0.01
                            ? Color.hpTextPrimary.opacity(0.5)
                            : Color.hpAccent
                    )
                    .frame(width: 10, height: 8)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .offset(y: height / 2 - CGFloat(fraction) * height)
            }
            .frame(width: geometry.size.width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = min(max(gesture.location.y, 0), height)
                        let fraction = Double(1 - clampedY / height)
                        let raw = range.lowerBound + fraction * span
                        let snapped = (raw / step).rounded() * step
                        value = min(max(snapped, range.lowerBound), range.upperBound)
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    value = 0
                }
            }
        }
    }
}

// MARK: - 流式布局（预设 chips 自动换行）

/// macOS 14 可用的 Layout 协议流式布局：子视图按行排布，放不下就换行。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : max(0, x - spacing)
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
