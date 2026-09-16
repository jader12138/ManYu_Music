import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case home
    case playback
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "外观"
        case .home: "首页"
        case .playback: "播放"
        case .library: "资料库"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .home: "house.fill"
        case .playback: "play.circle.fill"
        case .library: "music.note.list"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    @AppStorage(AppIconStyle.storageKey) private var appIconStyleRaw = AppIconStyle.automatic.rawValue
    @AppStorage(DockArtworkController.showsArtworkKey) private var showDockArtwork = true
    @AppStorage(AudioPlayer.rememberPlaybackKey) private var rememberPlaybackState = true
    @AppStorage(RecommendationSettings.frequencyKey)
    private var recommendationFrequencyRaw = RecommendationFrequency.daily.rawValue
    @AppStorage(RecommendationSettings.independentKey)
    private var recommendationIsIndependent = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab = .appearance

    var body: some View {
        VStack(spacing: 16) {
            settingsTabs

            ScrollView {
                Group {
                    switch selectedTab {
                    case .appearance:
                        appearanceSettings
                    case .home:
                        homeSettings
                    case .playback:
                        playbackSettings
                    case .library:
                        librarySettings
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var settingsTabs: some View {
        HStack(spacing: 5) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? .white : Color.hpTextPrimary.opacity(0.58))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            selectedTab == tab ? AnyShapeStyle(LinearGradient.hpAccentFill) : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.hpTextPrimary.opacity(0.05), in: Capsule())
        .overlay {
            Capsule().stroke(Color.hpTextPrimary.opacity(0.06), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceSettings: some View {
        VStack(spacing: 16) {
            settingsCard(
                title: "主题",
                subtitle: "选择应用白天或夜间的外观"
            ) {
                HStack(spacing: 8) {
                    ForEach(AppAppearance.allCases) { appearance in
                        choiceButton(
                            title: appearance.title,
                            systemImage: appearance.systemImage,
                            selected: theme.appearance == appearance
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                theme.appearance = appearance
                            }
                        }
                    }
                }
            }

            settingsCard(
                title: "应用图标",
                subtitle: "Dock 图标自动跟随主题，也可固定深色或浅色；左上角品牌图标始终跟随昼夜模式"
            ) {
                HStack(spacing: 20) {
                    ForEach(AppIconStyle.allCases) { style in
                        Button {
                            appIconStyleRaw = style.rawValue
                            DockArtworkController.shared.refreshSetting()
                            player.refreshDockIcon()
                            AppIconStyleManager.apply()
                        } label: {
                            VStack(spacing: 8) {
                                if let image = AppIconStyleManager.image(
                                    for: style,
                                    colorScheme: colorScheme
                                ) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 58, height: 58)
                                }

                                Text(style.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(
                                        appIconStyleRaw == style.rawValue
                                            ? Color.hpAccent
                                            : Color.hpTextPrimary.opacity(0.48)
                                    )
                            }
                            .padding(10)
                            .background(
                                appIconStyleRaw == style.rawValue
                                    ? Color.hpAccent.opacity(0.10)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var homeSettings: some View {
        VStack(spacing: 16) {
            settingsCard(
                title: "推荐切换频率",
                subtitle: "控制首页推荐曲目什么时候更换；切换页面时推荐保持不变"
            ) {
                HStack(spacing: 8) {
                    ForEach(RecommendationFrequency.allCases) { frequency in
                        choiceButton(
                            title: frequency.title,
                            systemImage: frequency.systemImage,
                            selected: recommendationFrequencyRaw == frequency.rawValue
                        ) {
                            recommendationFrequencyRaw = frequency.rawValue
                        }
                    }
                }
            }

            settingsCard(
                title: "播放同步",
                subtitle: "控制推荐歌曲与当前播放队列的关系"
            ) {
                Toggle("推荐歌曲独立于上一首、下一首", isOn: $recommendationIsIndependent)
                    .toggleStyle(.switch)

                Text("开启后，切歌、上一首和下一首都不会改变首页推荐歌曲。")
                    .font(.caption)
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
            }
        }
    }

    private var playbackSettings: some View {
        VStack(spacing: 16) {
            settingsCard(
                title: "Dock",
                subtitle: "播放时用当前专辑封面替换 Dock 图标"
            ) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.hpAccentFill.opacity(0.16))
                            .frame(width: 38, height: 38)
                        Image(systemName: "dock.rectangle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.hpAccent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("显示专辑封面")
                            .font(.system(size: 12, weight: .semibold))
                        Text("右下角会同步显示播放或暂停状态")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    }

                    Spacer()

                    Toggle("", isOn: $showDockArtwork)
                        .labelsHidden()
                        .onChange(of: showDockArtwork) { _, _ in
                            player.refreshDockIcon()
                        }
                }
            }

            settingsCard(
                title: "播放记忆",
                subtitle: "下次打开时恢复上次的歌曲和进度"
            ) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.hpAccent.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.hpAccent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("记住上次播放状态")
                            .font(.system(size: 12, weight: .semibold))
                        Text("重启后保持暂停，按空格从上次位置继续")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    }

                    Spacer()

                    Toggle("", isOn: $rememberPlaybackState)
                        .labelsHidden()
                        .onChange(of: rememberPlaybackState) { _, enabled in
                            if !enabled {
                                player.clearRememberedPlaybackState()
                            }
                        }
                }
            }

            settingsCard(
                title: "播放器状态",
                subtitle: "当前播放与睡眠定时信息"
            ) {
                VStack(spacing: 10) {
                    settingsRow(
                        title: "当前输出",
                        value: player.isPlaying ? "正在播放" : "已暂停",
                        valueColor: player.isPlaying ? Color.hpAccent : Color.hpTextPrimary.opacity(0.46)
                    )

                    Divider().opacity(0.08)

                    SleepTimerRow(clock: player.clock)
                }
            }
        }
    }

    private var librarySettings: some View {
        VStack(spacing: 16) {
            settingsCard(
                title: "添加音乐",
                subtitle: "从文件或文件夹导入本地音乐"
            ) {
                Button {
                    library.presentImportPanel()
                } label: {
                    HStack(spacing: 10) {
                        if library.isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.isImporting ? "正在导入…" : "添加音乐文件或文件夹")
                                .font(.system(size: 12, weight: .semibold))
                            Text("支持 MP3、FLAC、M4A、AAC、WAV、AIFF、CAF")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.28))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .background(Color.hpAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!library.canEdit || library.isImporting)
            }

            settingsCard(
                title: "本地资料库",
                subtitle: "当前资料库内容统计"
            ) {
                HStack(spacing: 10) {
                    statistic(value: "\(library.tracks.count)", title: "歌曲")
                    statistic(value: "\(Set(library.tracks.map(\.displayAlbum)).count)", title: "专辑")
                    statistic(value: "\(Set(library.tracks.map(\.displayArtist)).count)", title: "艺术家")
                }

                Button {
                    library.rescanLibrary()
                } label: {
                    Label(
                        library.isImporting ? "正在扫描…" : "重新扫描资料库",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(Color.hpAccent)
                    .background(Color.hpAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!library.canEdit || library.isImporting)
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.40))
            }

            content()
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.hpAccent.opacity(0.08), Color.hpSurface.opacity(0.42)]
                                    : [Color.white.opacity(0.58), Color.hpIce.opacity(0.34)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.hpTextPrimary.opacity(0.07), lineWidth: 1)
        }
    }

    private func choiceButton(
        title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundStyle(selected ? .white : Color.hpTextPrimary.opacity(0.62))
                .background(
                    selected ? AnyShapeStyle(LinearGradient.hpAccentFill) : AnyShapeStyle(Color.hpTextPrimary.opacity(0.045)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsRow(
        title: String,
        value: String,
        valueColor: Color
    ) -> some View {
        SettingsRowLabel(title: title, value: value, valueColor: valueColor)
    }

    private func statistic(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hpTextPrimary)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.40))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(Color.hpTextPrimary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Countdown kept in its own clock-observing view: the once-per-second tick then
/// invalidates this row only, not the whole settings screen.
private struct SleepTimerRow: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        SettingsRowLabel(
            title: "睡眠定时",
            value: clock.sleepTimerRemaining.map { "剩余 \(Int(ceil($0 / 60))) 分钟" } ?? "未开启",
            valueColor: Color.hpTextPrimary.opacity(0.46)
        )
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.58))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(valueColor)
        }
    }
}
