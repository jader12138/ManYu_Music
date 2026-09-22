import AppKit
import SwiftUI

/// 进入播放页的入口：决定大封面 matched geometry 的来源——
/// 播放栏小封面为「放大成长」，主页推荐大封面为「平移就位」。
enum NowPlayingEntry {
    case playerBar
    case homeHero
}

struct NowPlayingView: View {
    let transitionNamespace: Namespace.ID
    let artworkEntry: NowPlayingEntry

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingLyricsStyle = false
    /// 播放页内部视图模式：false = 封面+歌词，true = 队列选歌列表。
    /// 点列表 morph 钮在两种模式间切换，不离开播放页。
    @State private var showQueueList = false
    /// 歌词面板“呼吸”：连续快速切歌时歌词树原地不重建，只让整块歌词
    /// 的透明度短暂下沉再恢复，用合成层淡出盖住重排顿挫。
    @State private var lyricsDimmed = false
    @State private var lyricsDimmerGeneration = 0
    /// 歌词视图延迟挂载：LyricTimelineView 首次要测量全部歌词行（几百行 Text 布局），
    /// 若与进入播放页的转场挤在同一帧会造成可感的卡顿；先占位等高，落位后再淡入。
    @State private var lyricsReady = false
    @AppStorage("ManyuMusic.lyricsFontSize") private var lyricsFontSize = 18.0
    @AppStorage("ManyuMusic.lyricsFontDesign") private var lyricsFontDesignRaw = "rounded"
    @AppStorage("ManyuMusic.lyricsColor") private var lyricsColorRaw = "auto"
    @AppStorage("ManyuMusic.lyricsLineSpacing") private var lyricsLineSpacing = 0.9
    @AppStorage("ManyuMusic.lyricsVisibleLines") private var lyricsVisibleLines = 9.0

    var body: some View {
        ZStack {
            // 背景由 MainView 在 NowPlayingView 底下统一挂载（NowPlayingBackdrop），
            // 这里不再重复实例化：转场瞬间少一份全屏模糊封面 + 一组动画光斑的开销。

            GeometryReader { geometry in
                let artworkSize = min(
                    400,
                    max(190, min(geometry.size.height * 0.52, geometry.size.width * 0.30))
                )
                let lyricsHeight = min(640, max(260, geometry.size.height - 70))
                let horizontalPadding = max(24, min(52, geometry.size.width * 0.045))

                VStack(spacing: 0) {
                    Spacer(minLength: 78)

                    // 原始 HStack 布局：albumPanel（封面+控制栏）+ lyricsPanel
                    HStack(alignment: .center, spacing: max(24, horizontalPadding * 0.85)) {
                        albumPanel(artworkSize: artworkSize)
                            .frame(maxWidth: .infinity)

                        lyricsPanel
                            .frame(maxWidth: .infinity)
                            .frame(height: lyricsHeight)
                            .opacity(showQueueList ? 0 : 1)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .overlay(alignment: .top) {
                        // 队列列表 overlay：从顶部开始紧贴封面原来的位置，控制栏仍在下方原位。
                        // 水平额外 padding 让列表收窄往中间靠；只显示 currentIndex 之后的曲目。
                        queueListPanel
                            .frame(maxWidth: .infinity)
                            .frame(height: 440)
                            .padding(.horizontal, 80)
                            .opacity(showQueueList ? 1 : 0)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: showQueueList)
            }
        }
        .onAppear {
            if reduceMotion {
                lyricsReady = true
            } else {
                // 0.65s > 转场 spring 的 0.56s：歌词首次布局的重活落在动画结束后的
                // 静止画面里（淡入呈现），而不是与收尾帧争抢——避免"快到终点"的顿挫。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    withAnimation(.easeIn(duration: 0.25)) {
                        lyricsReady = true
                    }
                }
            }
        }
    }

    private func albumPanel(artworkSize: CGFloat) -> some View {
        VStack(spacing: 15) {
            // 封面+标题区：队列模式时隐藏，但控制栏位置不变。
            VStack(spacing: 15) {
                // 切歌过渡：新封面从旧封面「后面」被顶出来——下层封面轻微上浮+放大+淡入，
                // 前景的旧封面原地慢慢消散（不滑动）。ZStack 固定尺寸，不推动上下布局。
                ZStack {
                    ArtworkView(image: player.artwork, size: artworkSize, cornerRadius: 22)
                        .id(player.currentTrack?.id)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .asymmetric(
                                    insertion: .modifier(
                                        active: ArtworkPushInModifier(progress: 1),
                                        identity: ArtworkPushInModifier(progress: 0)
                                    ),
                                    removal: .modifier(
                                        active: ArtworkFadeOutModifier(progress: 1),
                                        identity: ArtworkFadeOutModifier(progress: 0)
                                    )
                                )
                        )
                }
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                // clipShape 会裁掉 ArtworkView 自带的外扩投影，在裁切层外补回同一投影，
                // 让切换中的封面被约束在圆角区域内、同时整体保留悬浮阴影。
                .shadow(color: .black.opacity(0.26), radius: 10, y: 6)
                .matchedGeometryEffect(
                    id: artworkEntry == .playerBar ? "nowPlayingArtwork.playerBar" : "nowPlayingArtwork.homeHero",
                    in: transitionNamespace,
                    isSource: false
                )
                // 减弱动态效果时立即替换；进/出播放页的放大转场期间曲目不变，互不影响。
                .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: player.currentTrack?.id)

                VStack(spacing: 8) {
                    Text(player.currentTrack?.displayTitle ?? "还未播放")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleGradient)
                        .animation(.easeInOut(duration: 0.65), value: player.currentTrack?.id)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)

                    Text(player.currentTrack?.displayArtist ?? "选择一首歌曲开始")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if let album = player.currentTrack?.displayAlbum {
                        Text(album)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.34))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 380)
            }
            .opacity(showQueueList ? 0 : 1)

            // 控制栏始终在封面下方原位，不随封面隐藏而移动。
            compactPlaybackControls
                .frame(maxWidth: min(400, artworkSize + 84))
        }
    }

    /// 歌曲标题渐变：封面主色与白色混合（浅色模式下文字端换成深色保证可读）。
    private var titleGradient: LinearGradient {
        let palette = player.artworkPalette ?? .fallback
        return LinearGradient(
            colors: [
                titleLightColor.opacity(0.95),
                Color(nsColor: palette.primary).opacity(0.92),
                Color(nsColor: palette.secondary).opacity(0.94)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var titleLightColor: Color {
        colorScheme == .dark ? .white : Color.hpTextPrimary
    }

    private var compactPlaybackControls: some View {
        VStack(spacing: 8) {
            PlaybackProgressRow(
                clock: player.clock,
                isEnabled: player.currentTrack != nil,
                seek: player.seek,
                isPlaying: player.isPlaying,
                isRapidSwitching: player.isRapidSwitching,
                controlSize: .small,
                fontWeight: .semibold
            )

            HStack(spacing: 16) {
                modeButton(
                    systemName: player.playbackMode.systemImage,
                    isActive: player.playbackMode != .sequential,
                    help: player.playbackMode.helpText
                ) {
                    player.cyclePlaybackMode()
                }
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                           value: player.playbackMode)

                queuePickerMorphButton

                IconButton(systemName: "backward.fill", help: "上一首", size: 14) {
                    player.previous()
                }
                .disabled(player.queue.isEmpty)

                Button {
                    player.togglePlayback()
                } label: {
                    PlaybackToggleSymbol(isPlaying: player.isPlaying, size: 14)
                        .frame(width: 38, height: 38)
                        .background(LinearGradient.hpAccentFill, in: Circle())
                        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
                }
                .buttonStyle(PlaybackPressButtonStyle(reduceMotion: reduceMotion))
                .disabled(player.currentTrack == nil)
                .help(player.isPlaying ? "暂停" : "播放")

                IconButton(systemName: "forward.fill", help: "下一首", size: 14) {
                    player.next()
                }
                .disabled(player.queue.isEmpty)

                IconButton(
                    systemName: isCurrentFavorite ? "heart.fill" : "heart",
                    isActive: isCurrentFavorite,
                    activeColor: .hpPink,
                    help: isCurrentFavorite ? "取消收藏" : "收藏",
                    size: 14
                ) {
                    if let track = player.currentTrack {
                        library.toggleFavorite(track)
                    }
                }
                .disabled(player.currentTrack == nil)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    /// 播放模式按钮：三态合一，循环切换，所有模式在图标下方都显示主题色小点
    /// （包括顺序播放——便于启动时一眼识别上次退出时的模式）。
    private func modeButton(
        systemName: String,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.85))
                .frame(width: 32, height: 32)
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(Color.hpAccent)
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: 2.5)
                }
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                           value: player.playbackMode)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// 列表 ⇄ 气泡融合切换钮：在播放页内部切换封面歌词 ↔ 队列选歌列表。
    /// 封面歌词模式显示列表图标，队列列表模式显示对白气泡，点击 morph 切换。
    private var queuePickerMorphButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                showQueueList.toggle()
            }
        } label: {
            Image(systemName: showQueueList ? "quote.bubble.fill" : "list.bullet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                .frame(width: 32, height: 32)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                           value: showQueueList)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showQueueList ? "回到播放页" : "选择播放歌曲")
    }

    /// 队列选歌列表：只显示接下来要播的歌曲（currentIndex 之后的曲目）。
    /// 顺序播放时按 queue 顺序依次是下一首、下下一首……
    /// 随机播放时顺序不可预知，但仍展示 queue 中剩余的候选曲目供切歌。
    private var queueListPanel: some View {
        let startIndex = (player.currentIndex ?? -1) + 1
        let upcoming: [Track] = Array(player.queue.dropFirst(max(0, startIndex)))

        return Group {
            if upcoming.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("没有更多歌曲了")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("从资料库选择更多歌曲来播放")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackListView(
                    tracks: upcoming,
                    showsHeader: false,
                    onRemoveTrack: { track in
                        guard let index = player.queue.firstIndex(where: { $0.id == track.id }) else { return }
                        player.removeFromQueue(at: IndexSet(integer: index))
                    },
                    removeTrackLabel: "从队列移除"
                ) { track in
                    guard let index = player.queue.firstIndex(where: { $0.id == track.id }) else { return }
                    player.playFromQueue(at: index)
                }
            }
        }
    }

    /// 音量控件已迁至底部播放条（PlayerBar.PlayerVolumeControl），播放页不再重复放置。

    private var isCurrentFavorite: Bool {
        player.currentTrack.map { library.isFavorite($0) } ?? false
    }

    private var lyricsFontDesign: Font.Design {
        switch lyricsFontDesignRaw {
        case "default": .default
        case "serif": .serif
        case "monospaced": .monospaced
        default: .rounded
        }
    }

    private var lyricsTextColor: Color {
        if lyricsColorRaw == "auto" {
            return Color.hpTextPrimary
        }
        return Color(hex: lyricsColorRaw) ?? Color.hpTextPrimary
    }

    private var lyricsStylePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("歌词样式")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button("重置") {
                    lyricsFontSize = 18
                    lyricsFontDesignRaw = "rounded"
                    lyricsColorRaw = "auto"
                    lyricsLineSpacing = 0.9
                    lyricsVisibleLines = 9
                }
                .buttonStyle(.link)
            }

            HStack(spacing: 12) {
                Text("字号")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                Button {
                    lyricsFontSize = max(13, lyricsFontSize - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)

                Text("\(Int(lyricsFontSize))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 28)

                Button {
                    lyricsFontSize = min(30, lyricsFontSize + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                Text("行距")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                Button {
                    lyricsLineSpacing = max(0.7, lyricsLineSpacing - 0.05)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)

                Text(String(format: "%.2f", lyricsLineSpacing))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 42)

                Button {
                    lyricsLineSpacing = min(1.4, lyricsLineSpacing + 0.05)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                Text("行数")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                Button {
                    lyricsVisibleLines = max(5, lyricsVisibleLines - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)

                Text("\(Int(lyricsVisibleLines))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 42)

                Button {
                    lyricsVisibleLines = min(13, lyricsVisibleLines + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("字体")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("字体", selection: $lyricsFontDesignRaw) {
                    Text("圆体").tag("rounded")
                    Text("默认").tag("default")
                    Text("衬线").tag("serif")
                    Text("等宽").tag("monospaced")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("颜色")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(lyricColorOptions, id: \.id) { option in
                        Button {
                            lyricsColorRaw = option.id
                        } label: {
                            Circle()
                                .fill(option.color)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            lyricsColorRaw == option.id ? Color.hpAccent : Color.primary.opacity(0.14),
                                            lineWidth: lyricsColorRaw == option.id ? 2.5 : 1
                                        )
                                }
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
            }

            Divider()

            // 歌词进度微调：与样式调节融合在同一个面板，步进 0.2 秒。
            HStack(spacing: 12) {
                Text("进度")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                Button {
                    player.adjustLyricOffset(-0.2)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(player.currentTrack == nil)
                .help("歌词提前 0.2 秒")

                Text(player.lyricOffset == 0
                     ? "已对齐"
                     : "\(player.lyricOffset > 0 ? "延后" : "提前") \(offsetText(player.lyricOffset))")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(player.lyricOffset == 0 ? Color.secondary : Color.hpAccent)
                    .frame(maxWidth: .infinity)

                Button {
                    player.adjustLyricOffset(0.2)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(player.currentTrack == nil)
                .help("歌词延后 0.2 秒")
            }

            // 常驻按钮：重置后仅置灰，面板高度不变、不跳动。
            Button {
                player.resetLyricOffset()
            } label: {
                Text("重置为已对齐")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(player.lyricOffset == 0 ? Color.hpTextPrimary.opacity(0.3) : Color.hpPink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.hpTextPrimary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .disabled(player.lyricOffset == 0)
        }
        .padding(18)
        .frame(width: 300)
    }

    private var lyricColorOptions: [(id: String, title: String, color: Color)] {
        [
            ("auto", "跟随主题", Color.hpTextPrimary),
            ("ffffff", "白色", .white),
            ("111827", "深色", Color(red: 0.07, green: 0.09, blue: 0.15)),
            ("5fb8ff", "天蓝", Color.hpAccent),
            ("ff5f96", "粉色", Color.hpPink),
            ("f2b84b", "金色", Color.hpGold)
        ]
    }

    /// 偏移秒数显示（保留 1 位小数）。
    private func offsetText(_ value: Double) -> String {
        String(format: "%.1fs", abs(value) < 0.001 ? 0 : value)
    }

    private var lyricsPanel: some View {
        VStack(spacing: 8) {
            Group {
                if player.lyricLines.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(player.lyricsResolved ? "本歌曲暂无歌词" : "正在载入歌词")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.64))
                        Text(
                            player.lyricsResolved
                                ? "未在歌曲内嵌信息或同名 LRC 文件中找到歌词。"
                                : "正在读取歌曲的内嵌歌词或同名 LRC 文件…"
                        )
                            .font(.system(size: 11))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                            .lineSpacing(5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if lyricsReady {
                    LyricTimelineView(
                        lines: player.lyricLines,
                        clock: player.clock,
                        seek: player.seek,
                        baseFontSize: CGFloat(lyricsFontSize),
                        fontDesign: lyricsFontDesign,
                        textColor: lyricsTextColor,
                        lineSpacingScale: CGFloat(lyricsLineSpacing),
                        visibleLineCount: Int(lyricsVisibleLines),
                        lyricOffset: player.lyricOffset
                    )
                    .transition(.opacity)
                } else {
                    // 转场期间占住同样的空间，歌词落位后原位淡入，布局不跳动。
                    Color.clear
                }
            }
            // 切歌瞬间内容透明度下沉到 0.5，0.14s 内恢复：纯合成层操作，
            // 歌词视图身份不变、零布局重建，连续切歌时用淡出盖住重排顿挫。
            .opacity(lyricsDimmed ? 0.5 : 1)
            .onChange(of: player.currentTrack?.id) {
                guard !reduceMotion else { return }
                lyricsDimmerGeneration += 1
                let generation = lyricsDimmerGeneration
                lyricsDimmed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    guard generation == lyricsDimmerGeneration else { return }
                    withAnimation(.easeInOut(duration: 0.14)) {
                        lyricsDimmed = false
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Text("点击歌词可跳转")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.24))

                Button {
                    showingLyricsStyle.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size")
                        Text("Aa")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.58))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                }
                .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 8))
                .help("歌词设置")
                .popover(isPresented: $showingLyricsStyle, arrowEdge: .trailing) {
                    lyricsStylePanel
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: 500, alignment: .topLeading)
    }
}

/// 上报所在位置的窗口坐标（AppKit 坐标系），供"点击热区外收起滑块"的判断使用。
struct VolumeFrameReporter: NSViewRepresentable {
    let onFrame: (CGRect?) -> Void

    func makeNSView(context: Context) -> FrameReporterView {
        let view = FrameReporterView()
        view.onFrameHandler = onFrame
        return view
    }

    func updateNSView(_ nsView: FrameReporterView, context: Context) {
        nsView.onFrameHandler = onFrame
        nsView.reportFrame()
    }

    final class FrameReporterView: NSView {
        var onFrameHandler: ((CGRect?) -> Void)?

        override func viewDidMoveToWindow() {
            reportFrame()
        }

        override func layout() {
            super.layout()
            reportFrame()
        }

        func reportFrame() {
            guard let window else {
                onFrameHandler?(nil)
                return
            }
            // convert(to: nil) 自动完成坐标系转换，零误差。
            onFrameHandler?(convert(bounds, to: nil))
        }
    }
}

/// 捕获悬停区域内的滚轮调整音量（收起状态专用，
/// 滑块展开后该层整体移除，避免拦截滑块的拖动手势）。
/// 点击（展开/收起）由 SwiftUI 手势处理，本层只负责滚轮——NSView 层若吞掉
/// mouseUp，祖先容器（播放条空白区域）的 tap 手势与展开逻辑无法做互斥裁决。
struct VolumeScrollCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.onScrollHandler = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCatcherView, context: Context) {
        nsView.onScrollHandler = onScroll
    }

    final class ScrollCatcherView: NSView {
        var onScrollHandler: ((Double) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            guard event.scrollingDeltaY != 0 else { return }
            // 上滚增大音量；普通滚轮一格约 0.1，触控板细粒度滚动按比例缩放。
            let delta = -event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 40 : 8)
            onScrollHandler?(delta)
        }
    }
}

struct NowPlayingBackdrop: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 背景渐变缓慢漂移的状态位：onAppear 置 true 后以 repeatForever 来回摆动。
    @State private var gradientDrift = false
    @State private var orbDrift = false
    /// 第二层渐变（accent 色光斑）的独立摆动，与主层节奏不同，
    /// 让背景看起来不是规则地整体旋转——两层各自走自己的相位。
    @State private var accentDrift = false

    /// 用户在设置里开启/关闭播放页背景动画。关闭时所有 drift 置 false、
    /// animation 修饰符传 nil，整个背景完全静止；开启时每层 duration
    /// 都在 9~16 秒区间，肉眼能直接看到颜色带在缓慢扫动。
    @AppStorage(BackdropAnimation.enabledKey) private var animationEnabled = true

    var body: some View {
        let palette = player.artworkPalette ?? .fallback
        let primary = Color(nsColor: palette.primary)
        let secondary = Color(nsColor: palette.secondary)
        let accent = Color(nsColor: palette.accent)
        let motionAllowed = animationEnabled && !reduceMotion

        ZStack {
            if let backdrop = player.backdropImage {
                // 预渲染模糊图：换歌时后台算好，转场首帧只是贴一张图。
                Image(nsImage: backdrop)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.16)
                    .opacity(colorScheme == .dark ? 0.55 : 0.38)
            } else if let artwork = player.artwork {
                // 模糊图尚未就绪（刚换歌的极短窗口）时的兜底：保持原实时模糊。
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 72)
                    .scaleEffect(1.16)
                    .opacity(colorScheme == .dark ? 0.55 : 0.38)
            }

            // 主层：三色线性渐变——primary→secondary→accent→navy，颜色更重。
            // 不再单一从主色到派生色的对称过渡，而是把抽取自封面不同区域的
            // 多种采样色按斜角铺成一条带，放大后旋转摆动产生颜色扫动。
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        primary.opacity(0.82),
                        secondary.opacity(0.55),
                        accent.opacity(0.46),
                        Color.hpNavyDeep.opacity(0.97)
                    ]
                    : [
                        primary.opacity(0.42),
                        secondary.opacity(0.30),
                        Color.white.opacity(0.78),
                        accent.opacity(0.22)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // 放大后摆动旋转：颜色带在屏幕上扫动（9 秒一个来回——肉眼可见）。
            // 角度幅度 ±115°，叠加偏移让整体不是纯旋转——看起来像颜色带
            // 在缓慢横向漂移，而不是规整地左右摆。
            .scaleEffect(2.4)
            .rotationEffect(.degrees(gradientDrift ? 115 : -115))
            .offset(
                x: gradientDrift ? 60 : -60,
                y: gradientDrift ? -28 : 28
            )
            .animation(
                motionAllowed
                    ? .easeInOut(duration: 9).repeatForever(autoreverses: true)
                    : nil,
                value: gradientDrift
            )

            // 第二层：accent 色的径向强调点，位置不对称（偏左下），
            // 节奏与主层不同（11s vs 9s）——两层相位错开后，
            // 颜色带的扫动看起来更不规律、不会呈现机械的左右对称。
            RadialGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.38 : 0.20),
                    accent.opacity(0)
                ],
                center: .init(x: 0.32, y: 0.72),
                startRadius: 80,
                endRadius: 540
            )
            .scaleEffect(1.8)
            .rotationEffect(.degrees(accentDrift ? -75 : 75))
            .offset(
                x: accentDrift ? -80 : 80,
                y: accentDrift ? 40 : -40
            )
            .animation(
                motionAllowed
                    ? .easeInOut(duration: 11).repeatForever(autoreverses: true)
                    : nil,
                value: accentDrift
            )

            // 光斑：优先用预烘焙的模糊图（进出转场 GPU 零滤镜成本），
            // 未就绪时回退原实时模糊。显示尺寸 = 直径 + 2×模糊外溢余量。
            Group {
                if let orb = player.orbPrimaryImage {
                    Image(nsImage: orb)
                        .resizable()
                        .frame(width: 1020, height: 1020)
                } else {
                    Circle()
                        .fill(primary)
                        .frame(width: 620, height: 620)
                        .blur(radius: 160)
                }
            }
            .opacity(colorScheme == .dark ? 0.32 : 0.22)
            .offset(
                x: 420 + (orbDrift ? 52 : -52),
                y: -340 + (orbDrift ? -36 : 36)
            )
            .animation(
                motionAllowed
                    ? .easeInOut(duration: 13).repeatForever(autoreverses: true)
                    : nil,
                value: orbDrift
            )

            Group {
                if let orb = player.orbSecondaryImage {
                    Image(nsImage: orb)
                        .resizable()
                        .frame(width: 835, height: 835)
                } else {
                    Circle()
                        .fill(secondary)
                        .frame(width: 460, height: 460)
                        .blur(radius: 150)
                }
            }
            .opacity(colorScheme == .dark ? 0.22 : 0.16)
            .offset(
                x: -430 + (orbDrift ? -44 : 44),
                y: 320 + (orbDrift ? 40 : -40)
            )
            .animation(
                motionAllowed
                    ? .easeInOut(duration: 16).repeatForever(autoreverses: true)
                    : nil,
                value: orbDrift
            )
        }
        .animation(.easeInOut(duration: 0.65), value: player.currentTrack?.id)
        .onAppear {
            // 关闭动画或 reduceMotion 时：所有 drift 都不置 true，
            // rotationEffect/offset 维持 false 分支的固定值，整个背景完全静止。
            guard motionAllowed else { return }
            gradientDrift = true
            orbDrift = true
            accentDrift = true
        }
        .onChange(of: animationEnabled) { _, enabled in
            // 用户切换开关时同步 drift 状态：
            // 开启 → drift=true 触发 repeatForever 循环；
            // 关闭 → drift=false，配合 nil 动画立刻静止在 false 分支位置。
            guard !reduceMotion else {
                gradientDrift = false
                orbDrift = false
                accentDrift = false
                return
            }
            gradientDrift = enabled
            orbDrift = enabled
            accentDrift = enabled
        }
    }
}

/// 播放页背景动画开关的存储键集中点。
enum BackdropAnimation {
    static let enabledKey = "ManyuMusic.nowPlayingBackdropAnimation"
}

struct NowPlayingHeaderControls: View {
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.down")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.34))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 1) {
                Text("正在播放")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.88))
                Text("漫域音乐")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.36))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .help("返回资料库")
    }
}

// MARK: - 播放页封面切歌转场

/// 新封面「从后面顶出来」：起始（progress=1）在下层、轻微偏下偏小且透明，
/// 动画到 progress=0 时上浮放大到正位、完全显现。zIndex 固定为 0（在后景）。
private struct ArtworkPushInModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 - 0.05 * progress)
            .offset(y: 14 * progress)
            .opacity(1.0 - progress)
            .zIndex(0)
    }
}

/// 旧封面「向左退散」：保持在前景（zIndex 1），随 progress 向左滑动并淡出，
/// 呈现被后面的新封面顶替、朝左侧消散退去的观感。
private struct ArtworkFadeOutModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .offset(x: -36 * progress)
            .opacity(1.0 - progress)
            .zIndex(1)
    }
}
