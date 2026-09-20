import SwiftUI

/// 均衡器面板：预设菜单 + 十段滑块 + 自定义预设保存/删除。
/// 设置页（独立「均衡器」页签）与底部播放栏的 EQ 弹窗共用。
/// `showsEnableToggle` 为 true 时（播放栏弹窗）顶部带启用开关，
/// 面板自身通过 @AppStorage 驱动刷新并调用 `player.setEQEnabled`。
struct EqualizerPanelView: View {
    @EnvironmentObject private var player: AudioPlayer
    @AppStorage(Equalizer.enabledKey) private var eqEnabled = false

    var showsEnableToggle = false
    var showsHint = true

    // 本地镜像（Equalizer 非 Observable，滑块绑定镜像状态手动同步）
    @State private var eqGains: [Double] = .init(repeating: 0, count: Equalizer.bandCount)
    @State private var eqPresetID = ""
    @State private var showSavePresetDialog = false
    @State private var newPresetName = ""

    var body: some View {
        let customPresets = player.equalizer.customPresets
        let selectedIsCustom = customPresets.contains { $0.id == eqPresetID }
        let displayName = eqPresetID == Equalizer.customCurveID
            ? "自定义"
            : player.equalizer.selectedPresetName()
        return VStack(alignment: .leading, spacing: 12) {
            if showsEnableToggle {
                HStack {
                    Text("启用均衡器")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary)
                    Spacer()
                    Toggle("", isOn: $eqEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: eqEnabled) { newValue in
                            player.setEQEnabled(newValue)
                        }
                }
                Divider().opacity(0.08)
            }

            HStack(spacing: 10) {
                Menu {
                    Section("预设") {
                        ForEach(Equalizer.builtInPresets) { preset in
                            Button(preset.name) {
                                player.equalizer.apply(preset: preset)
                                syncEQState()
                            }
                        }
                    }
                    if !customPresets.isEmpty {
                        Section("自定义预设") {
                            ForEach(customPresets) { preset in
                                Button(preset.name) {
                                    player.equalizer.apply(preset: preset)
                                    syncEQState()
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .medium))
                        Text(displayName)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color.hpTextPrimary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .fixedSize()

                Spacer()

                Button {
                    newPresetName = ""
                    showSavePresetDialog = true
                } label: {
                    Label("保存为预设", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("把当前曲线保存为命名自定义预设")

                if selectedIsCustom {
                    Button {
                        player.equalizer.removeCustomPreset(id: eqPresetID)
                        syncEQState()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("删除当前自定义预设")
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(0..<Equalizer.bandCount, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(Equalizer.bandLabels[index])
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                            .frame(width: 28, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { eqGains[index] },
                                set: { newValue in
                                    eqGains[index] = newValue
                                    player.equalizer.setGain(at: index, to: newValue)
                                    if eqPresetID != Equalizer.customCurveID {
                                        eqPresetID = Equalizer.customCurveID
                                    }
                                }
                            ),
                            in: Equalizer.gainRange,
                            step: 0.5
                        )
                        .tint(.hpAccent)
                        Text(String(format: "%+.1f", eqGains[index]))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(
                                abs(eqGains[index]) > 0.01
                                    ? Color.hpAccent
                                    : Color.hpTextPrimary.opacity(0.4)
                            )
                            .frame(width: 34, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }

            if showsHint {
                HStack {
                    Spacer()
                    Text("拖动各段滑块调整音色，范围 -12 ~ +12 dB；0 dB 为不增不减")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.35))
                }
            }
        }
        .onAppear(perform: syncEQState)
        .alert("保存自定义预设", isPresented: $showSavePresetDialog) {
            TextField("预设名称", text: $newPresetName)
            Button("保存") {
                player.equalizer.saveCustomPreset(named: newPresetName)
                syncEQState()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("以当前十条滑块的曲线保存，保存后可在上方菜单中随时切换")
        }
    }

    /// 把 Equalizer 里的真实状态同步到本地镜像（面板出现/预设切换后调用）。
    private func syncEQState() {
        eqGains = player.equalizer.gains
        eqPresetID = player.equalizer.selectedPresetID
    }
}
