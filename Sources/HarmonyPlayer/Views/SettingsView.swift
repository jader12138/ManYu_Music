import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case home
    case playback
    case equalizer
    case library
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "外观"
        case .home: "首页"
        case .playback: "播放"
        case .equalizer: "均衡器"
        case .library: "资料库"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .home: "house.fill"
        case .playback: "play.circle.fill"
        case .equalizer: "slider.horizontal.3"
        case .library: "music.note.list"
        case .about: "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    @AppStorage(AppIconStyle.storageKey) private var appIconStyleRaw = AppIconStyle.automatic.rawValue
    @AppStorage(DockArtworkController.showsArtworkKey) private var showDockArtwork = true
    @AppStorage(MenuBarPlayerController.enabledKey) private var menuBarPlayer = true
    @AppStorage(AudioPlayer.rememberPlaybackKey) private var rememberPlaybackState = true
    @AppStorage(ArtworkPreloader.enabledKey) private var preloadArtwork = false
    @AppStorage(BackdropAnimation.enabledKey) private var backdropAnimationEnabled = true
    @AppStorage(AudioPlayer.gaplessPlaybackKey) private var gaplessPlayback = false
    @AppStorage(AudioPlayer.crossfadeEnabledKey) private var crossfadeEnabled = false
    @AppStorage(AudioPlayer.crossfadeDurationKey) private var crossfadeDuration = AudioPlayer.defaultCrossfadeDuration
    @AppStorage(AudioPlayer.keepPlayingAfterWindowCloseKey) private var keepPlayingAfterWindowClose = false
    @AppStorage(RecommendationSettings.frequencyKey)
    private var recommendationFrequencyRaw = RecommendationFrequency.daily.rawValue
    @AppStorage(RecommendationSettings.independentKey)
    private var recommendationIsIndependent = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SettingsTab = .appearance
    @State private var showDuplicateReviewSheet = false

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
        .sheet(isPresented: $showDuplicateReviewSheet) {
            DuplicateReviewSheet(
                groups: library.detectDuplicateGroups(),
                hiddenCount: library.hiddenDuplicateIDs.count,
                onApply: { toHide in
                    library.hideDuplicates(toHide)
                },
                onResetHidden: {
                    library.clearHiddenDuplicates()
                }
            )
        }
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
        case .equalizer: equalizerSettingsPage
        case .library: libraryPane
        case .about: aboutPane
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

                HStack(alignment: .top, spacing: 18) {
                    ForEach(AppAppearance.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                theme.appearance = mode
                            }
                        } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    if let preview = mode.previewImage {
                                        Image(nsImage: preview)
                                            .resizable()
                                            .interpolation(.high)
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 132, height: 88)
                                            .clipped()
                                    } else {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(mode.previewBackground)
                                            .frame(width: 132, height: 88)
                                    }
                                }
                                .frame(width: 132, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

            // 菜单栏播放器
            row(title: "菜单栏播放控制",
                subtitle: "在系统菜单栏实时显示当前歌词与播放图标，点击图标弹出菜单") {
                Toggle("", isOn: Binding(
                    get: { menuBarPlayer },
                    set: { menuBarPlayer = $0; MenuBarPlayerController.shared.syncWithSetting() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            // 歌词切换效果：下拉菜单
            row(title: "歌词切换效果",
                subtitle: "菜单栏歌词切换时的过渡动画") {
                Picker("", selection: Binding(
                    get: { MenuBarPlayerController.lyricTransition },
                    set: { MenuBarPlayerController.lyricTransition = $0 }
                )) {
                    ForEach(MenuBarPlayerController.LyricTransition.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                // 宽度贴合最长选项「从左揭开」四字+箭头，不再占满整行。
                .frame(width: 88)
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

            // 关闭窗口后继续播放
            row(title: "关闭窗口后继续后台播放",
                subtitle: "开启后点击窗口红叉不会退出应用，音乐继续播放；点击 Dock 图标可重新打开窗口") {
                Toggle("", isOn: $keepPlayingAfterWindowClose)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider().opacity(0.08)

            // 无缝播放
            row(title: "无缝播放（Gapless）",
                subtitle: "自然连播时提前准备下一首，歌曲衔接处没有空隙，适合整张专辑连续听") {
                Toggle("", isOn: $gaplessPlayback)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider().opacity(0.08)

            // 淡入淡出
            row(title: "淡入淡出（Crossfade）",
                subtitle: "切歌时上一首渐弱、下一首渐强，重叠过渡；开启后自动连播也按此处理") {
                Toggle("", isOn: $crossfadeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if crossfadeEnabled {
                row(title: "淡入淡出时长",
                    subtitle: "两首歌重叠过渡的秒数") {
                    HStack(spacing: 10) {
                        Text("\(Int(crossfadeDuration)) 秒")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.6))
                            .frame(width: 38, alignment: .trailing)
                        Slider(
                            value: $crossfadeDuration,
                            in: AudioPlayer.crossfadeDurationRange,
                            step: 1
                        )
                        .frame(width: 150)
                    }
                }
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

            // 播放页背景动画
            row(title: "播放页背景动画",
                subtitle: "关闭后背景渐变完全静止；开启时颜色带缓慢扫动（设置仅影响播放页背景，不影响其他动画）") {
                Toggle("", isOn: $backdropAnimationEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider().opacity(0.08)

            // 睡眠定时
            SleepTimerRow(clock: player.clock)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 均衡器

    /// 独立均衡器页：面板自带头部（标题/运行状态/关闭EQ/重置）、
    /// 三页签、实时频谱、预设与 31 段调节，设置页直接整页嵌入。
    private var equalizerSettingsPage: some View {
        EqualizerPanelView()
            .padding(.vertical, 10)
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

            // 3. 重复歌曲过滤
            row(title: "过滤重复歌曲",
                subtitle: "标题去尾缀数字后相同且歌手/专辑一致、时长±2 秒视为重复；开启后可手动选择保留哪首，其余隐藏") {
                Toggle("", isOn: $library.duplicateFilterEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if library.duplicateFilterEnabled {
                Divider().opacity(0.08)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.hiddenDuplicateIDs.isEmpty
                             ? "暂未隐藏任何重复歌曲"
                             : "已隐藏 \(library.hiddenDuplicateIDs.count) 首重复歌曲")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.6))
                        Text("隐藏仅作用于显示，不从资料库删除")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.35))
                    }
                    Spacer()
                    Button {
                        showDuplicateReviewSheet = true
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.hpAccent)
                    .disabled(library.tracks.count < 2 || library.isLoading)
                }
                .padding(.vertical, 8)
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

    // MARK: - 关于

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeading("关于")

            HStack(spacing: 18) {
                Image(nsImage: AppInfo.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("漫域音乐")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.hpTextPrimary)
                    HStack(spacing: 8) {
                        Text("版本 \(AppInfo.releaseName)（build \(AppInfo.buildNumber)）")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                        if AppInfo.isPrerelease {
                            Text("内部测试版")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.hpGold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.hpGold.opacity(0.15),
                                            in: Capsule(style: .continuous))
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            Divider().opacity(0.08)

            if AppInfo.isPrerelease {
                VStack(alignment: .leading, spacing: 6) {
                    Text("这是内部测试版本，可能存在不稳定的情况。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.6))
                    Text("欢迎把遇到的问题和建议反馈给我们，正式版发布前会持续修复。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.6))
                }

                Button {
                    if let url = URL(string: "https://github.com/jader12138/ManYu_Music/issues") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("在 GitHub 上反馈问题", systemImage: "ant.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(height: 30)
                        .padding(.horizontal, 14)
                        .foregroundStyle(Color.hpAccent)
                        .background(Color.hpAccent.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Divider().opacity(0.08)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("适用系统：macOS 14.0 及以上（Apple 芯片）")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                if let copyright = AppInfo.copyright {
                    Text(copyright)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                }
            }
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

// MARK: - AppInfo

/// 从 Bundle 读取版本/构建信息。`ManyuMusicReleaseName` 由构建脚本写入，
/// 形如 `3.13.0` 或内测期的 `3.13.0-beta1`；带 "-" 后缀时视为预发布版本。
enum AppInfo {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var releaseName: String {
        Bundle.main.object(forInfoDictionaryKey: "ManyuMusicReleaseName") as? String
            ?? marketingVersion
    }

    static var isPrerelease: Bool {
        releaseName.contains("-")
    }

    static var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    static var icon: NSImage {
        NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage
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

    /// 设置页外观预览缩略图（Resources/Appearance{System,Light,Dark}.png，
    /// 打包脚本安装进 Bundle）。取不到时回退到旧色块占位。
    var previewImage: NSImage? {
        let name: String
        switch self {
        case .system: name = "AppearanceSystem"
        case .light: name = "AppearanceLight"
        case .dark: name = "AppearanceDark"
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: name)
    }
}

// MARK: - 重复歌曲审查面板

/// 重复歌曲检测与手动保留选择面板。
///
/// 一次列出所有检测到的重复组，用户对每组单选「保留哪一首」；
/// 未被保留的歌曲 id 在「应用」时一次性加入隐藏集合，从浏览列表中隐藏。
struct DuplicateReviewSheet: View {
    let groups: [[Track]]
    let hiddenCount: Int
    let onApply: (Set<UUID>) -> Void
    let onResetHidden: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [Int: UUID] = [:]
    @State private var didInitSelections = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.12)

            if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                            groupView(idx: idx, group: group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }

            Divider().opacity(0.12)

            footer
        }
        .frame(width: 600, height: 520)
        .background(Color.hpSurface)
        .onAppear {
            if !didInitSelections {
                for (idx, group) in groups.enumerated() {
                    selections[idx] = group.first?.id
                }
                didInitSelections = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.hpAccent)
            Text("重复歌曲检测")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hpTextPrimary)
            Spacer()
            if hiddenCount > 0 {
                Text("已隐藏 \(hiddenCount) 首")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.hpAccent.opacity(0.7))
            Text("未发现重复歌曲")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
            if hiddenCount > 0 {
                Text("已隐藏的 \(hiddenCount) 首不在本次检测范围内")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if hiddenCount > 0 {
                Button {
                    onResetHidden()
                    dismiss()
                } label: {
                    Text("重置已隐藏")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))

            if !groups.isEmpty {
                Button {
                    var toHide: Set<UUID> = []
                    for (idx, group) in groups.enumerated() {
                        let keepID = selections[idx] ?? group.first?.id
                        guard let keepID else { continue }
                        for track in group where track.id != keepID {
                            toHide.insert(track.id)
                        }
                    }
                    if !toHide.isEmpty {
                        onApply(toHide)
                    }
                    dismiss()
                } label: {
                    Text("应用并隐藏未选中项")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.hpAccent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.hpAccent)
                .keyboardShortcut(.return)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func groupView(idx: Int, group: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("第 \(idx + 1) 组")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hpAccent)
                Text("\(group.count) 首可能重复")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.5))
                Spacer()
                if let representative = group.first {
                    Text(representative.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            VStack(spacing: 4) {
                ForEach(group) { track in
                    rowView(track: track,
                           isSelected: selections[idx] == track.id) {
                        selections[idx] = track.id
                    }
                }
            }
        }
        .padding(12)
        .background(Color.hpAccent.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.hpAccent.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func rowView(
        track: Track,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.hpAccent : Color.hpTextPrimary.opacity(0.3))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.hpTextPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(track.displayArtist)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                            .lineLimit(1)
                        Text("·").font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.3))
                        Text(track.displayAlbum)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                            .lineLimit(1)
                        Text("·").font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.3))
                        Text(track.formattedDuration)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
                    }
                    Text(track.url.lastPathComponent)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.32))
                        .lineLimit(1)
                }

                Spacer()
                Text(track.dateAdded.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                isSelected ? Color.hpAccent.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

