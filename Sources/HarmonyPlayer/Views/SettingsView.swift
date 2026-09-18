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
    @AppStorage(ArtworkPreloader.enabledKey) private var preloadArtwork = false
    @AppStorage(RecommendationSettings.frequencyKey)
    private var recommendationFrequencyRaw = RecommendationFrequency.daily.rawValue
    @AppStorage(RecommendationSettings.independentKey)
    private var recommendationIsIndependent = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab = .appearance

    var body: some View {
        HStack(spacing: 0) {
            sidebarList
                .frame(width: 180)

            ScrollView {
                contentPane
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 侧边栏（纯文字列表 + 左侧蓝色竖线选中）

    private var sidebarList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                sidebarRow(for: tab)
            }
            Spacer()
        }
        .padding(.top, 24)
        .padding(.leading, 16)
        .padding(.trailing, 8)
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                // 选中时的蓝色竖线
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(LinearGradient.hpAccentFill)
                    }
                }
                .frame(width: 3, height: 14)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)

                Text(tab.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected
                            ? Color.hpAccent
                            : Color.hpTextPrimary.opacity(0.65)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 右侧内容

    @ViewBuilder
    private var contentPane: some View {
        switch selectedTab {
        case .appearance: appearancePane
        case .home: homePane
        case .playback: playbackPane
        case .library: libraryPane
        }
    }

    // MARK: - 通用组件：分组标题（带左侧蓝色竖线）

    private func sectionHeading(_ text: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(LinearGradient.hpAccentFill)
                .frame(width: 3, height: 16)
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hpAccent)
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    // MARK: - 外观

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 28) {
            sectionHeading("外观")

            // 外观预览
            VStack(alignment: .leading, spacing: 12) {
                Text("外观")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.7))

                HStack(spacing: 14) {
                    ForEach(AppAppearance.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                theme.appearance = mode
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(mode.previewBackground)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(
                                            mode == .light
                                                ? Color.black.opacity(0.35)
                                                : Color.white.opacity(0.55)
                                        )
                                }
                                .frame(width: 70, height: 46)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            theme.appearance == mode
                                                ? Color.hpAccent
                                                : Color.hpTextPrimary.opacity(0.12),
                                            lineWidth: theme.appearance == mode ? 2 : 0.5
                                        )
                                )
                                Text(mode.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(
                                        theme.appearance == mode
                                            ? Color.hpAccent
                                            : Color.hpTextPrimary.opacity(0.5)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().opacity(0.08)

            // 应用图标
            VStack(alignment: .leading, spacing: 12) {
                Text("应用图标")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.7))

                HStack(spacing: 16) {
                    ForEach(AppIconStyle.allCases) { style in
                        Button {
                            appIconStyleRaw = style.rawValue
                            DockArtworkController.shared.refreshSetting()
                            player.refreshDockIcon()
                            AppIconStyleManager.apply()
                        } label: {
                            VStack(spacing: 6) {
                                if let image = AppIconStyleManager.image(
                                    for: style,
                                    colorScheme: colorScheme
                                ) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 50, height: 50)
                                }

                                Text(style.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(
                                        appIconStyleRaw == style.rawValue
                                            ? Color.hpAccent
                                            : Color.hpTextPrimary.opacity(0.5)
                                    )
                            }
                            .padding(8)
                            .background(
                                appIconStyleRaw == style.rawValue
                                    ? Color.hpAccent.opacity(0.10)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 首页

    private var homePane: some View {
        VStack(alignment: .leading, spacing: 28) {
            sectionHeading("首页推荐")

            // 推荐频率
            row(title: "推荐切换频率",
                subtitle: "控制首页推荐曲目什么时候更换") {
                HStack(spacing: 6) {
                    ForEach(RecommendationFrequency.allCases) { f in
                        Button {
                            recommendationFrequencyRaw = f.rawValue
                        } label: {
                            Text(f.title)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(height: 28)
                                .padding(.horizontal, 12)
                                .foregroundStyle(
                                    recommendationFrequencyRaw == f.rawValue
                                        ? .white
                                        : Color.hpTextPrimary.opacity(0.6)
                                )
                                .background(
                                    recommendationFrequencyRaw == f.rawValue
                                        ? AnyShapeStyle(LinearGradient.hpAccentFill)
                                        : AnyShapeStyle(Color.hpTextPrimary.opacity(0.05)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().opacity(0.08)

            // 独立于上下首
            row(title: "独立于上一首 / 下一首",
                subtitle: "开启后切歌不会改变首页推荐") {
                Toggle("", isOn: $recommendationIsIndependent)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 播放

    private var playbackPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("播放")

            // Dock 封面
            row(title: "Dock 显示专辑封面",
                subtitle: "播放时用当前专辑封面替换 Dock 图标，右下角显示播放状态") {
                Toggle("", isOn: Binding(
                    get: { showDockArtwork },
                    set: { showDockArtwork = $0; player.refreshDockIcon() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider().opacity(0.08)

            // 记忆状态
            row(title: "记住上次播放状态",
                subtitle: "下次打开时恢复上次的歌曲和进度") {
                Toggle("", isOn: Binding(
                    get: { rememberPlaybackState },
                    set: { v in rememberPlaybackState = v; if !v { player.clearRememberedPlaybackState() } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider().opacity(0.08)

            // 当前状态
            row(title: "当前状态") {
                Text(player.isPlaying ? "播放中" : "已暂停")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        player.isPlaying ? Color.hpAccent : Color.hpTextPrimary.opacity(0.45)
                    )
            }

            Divider().opacity(0.08)

            // 睡眠定时
            SleepTimerRow(clock: player.clock)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 资料库

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("资料库")

            // 1. 预加载（第一个）
            row(title: "启动时预加载封面",
                subtitle: "提前把封面读入缓存，浏览更快") {
                Toggle("", isOn: Binding(
                    get: { preloadArtwork },
                    set: { v in preloadArtwork = v
                           if v { ArtworkPreloader.shared.preloadIfNeeded(tracks: library.tracks) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider().opacity(0.08)

            // 2. 不扫描短音频
            row(title: "不扫描 60 秒以下的音频",
                subtitle: "导入时自动过滤掉很短的音频片段") {
                Toggle("", isOn: $library.filterShortAudio)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider().opacity(0.08)

            // 3. 屏蔽文件夹
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("屏蔽文件夹")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary)
                    Spacer()
                    Button {
                        presentBlockFolderPanel()
                    } label: {
                        Label("添加", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.hpAccent)
                }
                .padding(.vertical, 10)

                if library.blockedFolderPaths.isEmpty {
                    Text("暂无屏蔽")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                } else {
                    VStack(spacing: 0) {
                        ForEach(library.blockedFolderPaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.orange.opacity(0.8))
                                Text(path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    library.removeBlockedFolder(path: path)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.hpTextPrimary.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            Divider().opacity(0.08)

            // 2. 添加音乐 + 来源列表 + 资料库统计
            VStack(alignment: .leading, spacing: 18) {
                // 添加音乐按钮
                HStack {
                    Text("添加音乐")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
                    Spacer()
                    Button {
                        library.presentImportPanel()
                    } label: {
                        HStack(spacing: 6) {
                            if library.isImporting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(library.isImporting ? "正在导入…" : "添加文件或文件夹")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.hpAccent)
                        .frame(height: 28)
                        .padding(.horizontal, 12)
                        .background(Color.hpAccent.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!library.canEdit || library.isImporting)
                }
                .padding(.top, 6)

                // 来源列表
                if library.sources.isEmpty {
                    Text("还没有添加任何文件夹或文件")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                } else {
                    VStack(spacing: 0) {
                        ForEach(library.sources) { src in
                            HStack {
                                Image(systemName: src.isDirectory ? "folder.fill" : "music.note")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.hpAccent.opacity(0.8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(src.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.hpTextPrimary)
                                    Text(src.path)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.hpTextPrimary.opacity(0.35))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    library.removeLibrarySource(src)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }

                // 资料库统计
                HStack(spacing: 10) {
                    statistic(value: "\(library.tracks.count)", title: "歌曲")
                    statistic(value: "\(Set(library.tracks.map(\.displayAlbum)).count)", title: "专辑")
                    statistic(value: "\(Set(library.tracks.map(\.displayArtist)).count)", title: "艺术家")
                }

                // 重新扫描
                Button {
                    library.rescanLibrary()
                } label: {
                    Label(
                        library.isImporting ? "正在扫描…" : "重新扫描资料库",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .frame(height: 32)
                    .padding(.horizontal, 14)
                    .foregroundStyle(Color.hpAccent)
                    .background(Color.hpAccent.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!library.canEdit || library.isImporting)
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 通用：设置行（标题 + 可选副标题 + 右侧控件）

    // MARK: - 辅助：打开文件夹选择面板加入屏蔽

    private func presentBlockFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要屏蔽的文件夹"
        panel.prompt = "屏蔽"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.directory]
        panel.level = .floating
        panel.begin { [weak library] response in
            guard response == .OK else { return }
            for url in panel.urls {
                library?.addBlockedFolder(path: url.path)
            }
        }
    }

    private func row<Right: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            right()
        }
        .padding(.vertical, 12)
    }

    private func statistic(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hpTextPrimary)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Color.hpTextPrimary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 睡眠定时（扁平行版本）

private struct SleepTimerRow: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("睡眠定时")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary)
            }
            Spacer(minLength: 8)
            Text(clock.sleepTimerRemaining.map { "剩余 \(Int(ceil($0 / 60))) 分钟" } ?? "未开启")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
        }
        .padding(.vertical, 12)
    }
}

// MARK: - AppAppearance Preview

private extension AppAppearance {
    var previewBackground: Color {
        switch self {
        case .light: return Color(white: 0.95)
        case .dark: return Color(white: 0.1)
        case .system: return Color.gray.opacity(0.3)
        }
    }
}
