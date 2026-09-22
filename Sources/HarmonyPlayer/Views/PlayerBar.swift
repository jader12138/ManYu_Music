import AppKit
import SwiftUI

struct PlayerBar: View {
    @Binding var showQueue: Bool
    @Binding var showNowPlaying: Bool
    let transitionNamespace: Namespace.ID
    /// 进入播放页前（同一动画事务内）标记入口，让大封面用「放大成长」的几何来源。
    var onNowPlayingEntrySelected: () -> Void = {}

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isPlaybackControlFocused: Bool

    @AppStorage(Equalizer.enabledKey) private var eqEnabled = false
    @State private var showEQPopover = false
    @AppStorage(MenuBarPlayerController.lyricsVisibleKey) private var menuBarLyricsVisible = true

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 1040 {
                    wideContent
                } else {
                    compactContent
                }
            }
            .padding(.horizontal, geometry.size.width >= 1040 ? 18 : 12)
            .frame(width: geometry.size.width, height: geometry.size.height)
            // 点击播放条空白区域进入播放页：Button/IconButton/Menu 等带
            // 自身手势的子视图会优先吞掉点击，因此空白处（Spacer、padding、
            // 非按钮区域）的 tap 才会落到这一层 contentShape 上。
            // 进度条用 DragGesture(minimumDistance: 0) 也已拦截点击，
            // 不会被误识别为「进播放页」。
            .contentShape(Rectangle())
            .onTapGesture {
                guard player.currentTrack != nil else { return }
                withAnimation(.spring(response: 0.56, dampingFraction: 0.86)) {
                    onNowPlayingEntrySelected()
                    showNowPlaying = true
                }
            }
        }
        .frame(height: 72)
        .onAppear {
            focusPlaybackControl()
        }
        .onChange(of: player.currentTrack?.id) { _, _ in
            focusPlaybackControl()
        }
        .background {
            Color.hpSurface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.hpHairline)
                        .frame(height: 1)
                }
        }
    }

    private var wideContent: some View {
        HStack(spacing: 18) {
            // 红圈曲目区（封面+歌名+格式徽标+歌手名）整体右移 20pt：
            // padding 加在 frame 内侧，外部 280 定宽不变，不挤压中央控件。
            nowPlaying
                .padding(.leading, 20)
                .frame(width: 280, alignment: .leading)

            Spacer(minLength: 12)

            controls
                .frame(maxWidth: 540)

            Spacer(minLength: 12)

            utilities
                .frame(width: 280, alignment: .trailing)
        }
    }

    private var compactContent: some View {
        // 窄屏布局与宽屏同构：两侧定宽、中央控件靠 Spacer 居中。
        // 旧实现把曲目区设为 infinity，标题与格式徽标之间被撑出巨大空隙，
        // 控件也被挤到右侧——窗口 840~1040pt 时播放条看起来像"变形"。
        HStack(spacing: 12) {
            nowPlaying
                .padding(.leading, 20)
                .frame(width: 240, alignment: .leading)

            Spacer(minLength: 8)

            controls
                .frame(maxWidth: 380)

            Spacer(minLength: 8)

            compactUtilities
                .frame(width: 78, alignment: .trailing)
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Button {
                guard player.currentTrack != nil else { return }
                withAnimation(.spring(response: 0.56, dampingFraction: 0.86)) {
                    onNowPlayingEntrySelected()
                    showNowPlaying.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    // 亚克力包边：玻璃底 + 白色微光 + 一圈很细的灰线（自适应深浅模式），
                    // 按小封面等比缩小——hero 每边宽 11pt，这里每边 3pt（外框 54、封面 48）；
                    // 白色封面也能凭灰线清楚看到边界。包边不参与 matchedGeometry 转场，
                    // 进播放页时只放大封面、包边留在播放条。
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.hpHairline, lineWidth: 0.6)
                                    .shadow(color: .black.opacity(0.38), radius: 0.9, y: 0.9)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)

                        // 圆角基准：7:48，全局其他封面（播放页大封面除外）都按此比例统一。
                        ArtworkView(image: player.artwork, size: 48, cornerRadius: ArtworkLayout.cornerRadius(for: 48))
                            .matchedGeometryEffect(id: "nowPlayingArtwork.playerBar", in: transitionNamespace, isSource: true)
                    }
                    .frame(width: 54, height: 54)

                    if let track = player.currentTrack {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(track.displayTitle)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.hpTextPrimary)
                                        .lineLimit(1)
                                    // 格式徽标紧贴歌名右侧，往下微调使其视觉居中于
                                    // 歌名与歌手名两行之间，而不是漂在右侧远离文字。
                                    formatBadge(for: track)
                                        .offset(y: 5)
                                }
                                Text(track.displayArtist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.hpTextPrimary.opacity(0.44))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("还没有播放歌曲")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.hpTextPrimary.opacity(0.62))
                            Text("从资料库中选择一首开始")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.hpTextPrimary.opacity(0.34))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .help("打开播放页")
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)
        }
    }

    private var controls: some View {
        VStack(spacing: 5) {
            HStack(spacing: 15) {
                // 三态播放模式按钮（与播放页一致：顺序→单曲循环→随机，循环切换，
                // 当前模式在图标下方显示主题色小点——所有模式都显示，方便恢复时识别）。
                Button {
                    player.cyclePlaybackMode()
                } label: {
                    Image(systemName: player.playbackMode.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .overlay(alignment: .bottom) {
                            Circle()
                                .fill(Color.hpAccent)
                                .frame(width: 3.5, height: 3.5)
                                .offset(y: -2.5)
                        }
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                                   value: player.playbackMode)
                }
                .buttonStyle(.plain)
                .help(player.playbackMode.helpText)

                IconButton(systemName: "backward.fill", help: "上一首", size: 15) {
                    player.previous()
                }
                .disabled(player.queue.isEmpty)

                Button {
                    player.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.hpAccentFill)
                            .frame(width: 32, height: 32)
                            .shadow(color: Color.hpAccent.opacity(0.24), radius: 7, y: 3)
                        PlaybackToggleSymbol(isPlaying: player.isPlaying, size: 12, offsetWhenPaused: 1)
                    }
                }
                .buttonStyle(PlaybackPressButtonStyle(reduceMotion: reduceMotion))
                .focusable()
                .focused($isPlaybackControlFocused)
                .focusEffectDisabled()
                .disabled(player.currentTrack == nil)
                .help(player.isPlaying ? "暂停" : "播放")

                IconButton(systemName: "forward.fill", help: "下一首", size: 15) {
                    player.next()
                }
                .disabled(player.queue.isEmpty)

                IconButton(
                    systemName: (player.currentTrack.flatMap { library.isFavorite($0) } ?? false) ? "heart.fill" : "heart",
                    isActive: (player.currentTrack.flatMap { library.isFavorite($0) } ?? false),
                    activeColor: .hpPink,
                    help: (player.currentTrack.flatMap { library.isFavorite($0) } ?? false) ? "取消收藏" : "收藏",
                    size: 13
                ) {
                    if let track = player.currentTrack {
                        library.toggleFavorite(track)
                    }
                }
                .disabled(player.currentTrack == nil)

                lyricsButton
            }

            PlaybackProgressRow(
                clock: player.clock,
                isEnabled: player.currentTrack != nil,
                seek: player.seek,
                isPlaying: player.isPlaying,
                isRapidSwitching: player.isRapidSwitching
            )
        }
    }

    private func formatBadge(for track: Track) -> some View {
        let color = Color.formatColor(forExtension: track.url.pathExtension)
        return Text(track.url.pathExtension.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }

    /// 菜单栏歌词开关：位于「喜欢」爱心右侧；开启时「词」字底部出现小蓝点，
    /// 关闭时蓝点消失（无高亮底色）。
    private var lyricsButton: some View {
        IconButton(
            textLabel: "词",
            isActive: menuBarLyricsVisible,
            showsActivityDot: true,
            help: menuBarLyricsVisible ? "隐藏菜单栏歌词" : "显示菜单栏歌词",
            size: 13
        ) {
            MenuBarPlayerController.shared.toggleLyricsVisible()
        }
    }

    /// 均衡器按钮：点击弹出轻量 EQ 面板（与设置页共用 EqualizerPanelView）。
    /// EQ 开启时按钮保持高亮，位于「定时」左侧。
    private var eqButton: some View {
        IconButton(
            systemName: "slider.horizontal.3",
            isActive: eqEnabled,
            help: eqEnabled ? "均衡器（已开启）" : "均衡器",
            size: 13
        ) {
            showEQPopover.toggle()
        }
        .popover(isPresented: $showEQPopover, arrowEdge: .bottom) {
            EqualizerPanelView(
                showsCloseButton: true,
                onClose: { showEQPopover = false }
            )
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("关闭定时") {
                player.setSleepTimer(minutes: nil)
            }
            .disabled(player.sleepTimerEnd == nil)

            Divider()

            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("\(minutes) 分钟") {
                    player.setSleepTimer(minutes: minutes)
                }
            }
        } label: {
            SleepTimerLabel(clock: player.clock, isActive: player.sleepTimerEnd != nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34)
        .help("睡眠定时")
    }

    private var compactUtilities: some View {
        HStack(spacing: 2) {
            eqButton

            sleepTimerMenu

            // 音量控件：喇叭 + 右侧常驻滑条（拖动/悬停滚轮均可调）。
            BarVolumeControl()

            IconButton(
                systemName: "list.bullet",
                isActive: showQueue,
                help: showQueue ? "隐藏播放队列" : "显示播放队列",
                size: 13
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showQueue.toggle()
                }
            }
        }
    }

    private var utilities: some View {
        HStack(spacing: 8) {
            eqButton

            sleepTimerMenu

            BarVolumeControl()

            IconButton(
                systemName: "list.bullet",
                isActive: showQueue,
                help: showQueue ? "隐藏播放队列" : "显示播放队列",
                size: 13
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showQueue.toggle()
                }
            }
        }
    }

    private func focusPlaybackControl() {
        for delay in [0.12, 0.45, 0.9, 1.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard player.currentTrack != nil else { return }
                NSApp.keyWindow?.makeFirstResponder(nil)
                isPlaybackControlFocused = true
            }
        }
    }
}

// MARK: - Clock-scoped playback widgets

/// Elapsed/total time plus the scrubber, shared by the player bar and the
/// now-playing panel.
///
/// This is deliberately the only progress-aware view: it observes
/// `PlaybackClock` so the 0.25s tick invalidates just this row rather than the
/// whole player bar or now-playing hierarchy. The scrub position stays local
/// here, so dragging is unaffected by clock updates.
struct PlaybackProgressRow: View {
    @ObservedObject var clock: PlaybackClock
    let isEnabled: Bool
    let seek: (Double) -> Void
    var isPlaying: Bool = false
    /// 快速连切中：插值必须冻结，且锚点重钉到真实媒体时间。
    var isRapidSwitching: Bool = false
    var controlSize: ControlSize = .mini
    var fontWeight: Font.Weight = .medium

    /// 航位推算锚点：媒体时间 anchorTime 对应的"应到墙钟时刻" anchorWall。
    ///
    /// 时钟回调经 `Task { @MainActor }` 投递，到达时刻天然抖动；若每次
    /// tick 都用"当前墙钟"重设锚点，投递延迟的波动会直接变成显示时间的
    /// 回跳（锯齿）。这里改为按媒体时间推进锚点墙钟（anchorWall +=
    /// clockDelta），投递早晚完全不影响显示；seek/切歌/暂停恢复时
    /// （媒体推进与墙钟推进脱钩）才整体重同步。
    @State private var anchorTime: Double = 0
    @State private var anchorWall = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            // 快切中即使 isPlaying 的 KVO 还没来得及翻成 false，也强制冻结：
            // 不能把切歌占用的墙钟时间误记成播放进度。
            let advancing = isPlaying && !isRapidSwitching
            let raw = advancing ? anchorTime + context.date.timeIntervalSince(anchorWall) : anchorTime
            let displayed = clock.duration > 0 ? min(max(raw, 0), clock.duration) : max(raw, 0)
            HStack(spacing: 8) {
                Text(Track.formatTime(displayed))
                    .font(.system(size: 9, weight: fontWeight, design: .monospaced))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                    .frame(width: 40, alignment: .trailing)

                SmoothScrubber(
                    progress: clock.duration > 0 ? min(max(displayed / clock.duration, 0), 1) : 0,
                    duration: clock.duration,
                    isEnabled: isEnabled,
                    seek: seek
                )
                .disabled(!isEnabled)

                Text(clock.duration > 0 ? Track.formatTime(clock.duration) : "--:--")
                    .font(.system(size: 9, weight: fontWeight, design: .monospaced))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                    .frame(width: 40, alignment: .leading)
            }
        }
        .onAppear {
            anchorTime = clock.currentTime
            anchorWall = Date()
        }
        .onChange(of: isRapidSwitching) {
            // 快切开始：钉在当前真实媒体时间（load 已置 0）并冻结；
            // 快切结束（恢复播放前）：再钉一次真实值，新曲目从 0 平滑起步，
            // 不会出现“虚走到几秒、恢复后被 tick 拽回 0”的跳变。
            anchorTime = clock.currentTime
            anchorWall = Date()
        }
        .onChange(of: clock.currentTime) { old, new in
            let wallNow = Date()
            let clockDelta = new - old
            let advancing = isPlaying && !isRapidSwitching
            // 显示值与真实媒体时间的绝对偏差兜底：tick 投递到主线程的延迟
            // 会逐次累积在锚点墙钟里（每次只差几十毫秒，单次偏差阈值永远
            // 触发不了），显示值跟着墙钟越跑越超前——进度条先于歌曲到达
            // 末尾、与歌词错位。用绝对偏差兜底后，累积误差最多存活 0.25s
            // 即被清零，tick 间的插值平滑保持不变。
            let displayedNow = advancing
                ? anchorTime + wallNow.timeIntervalSince(anchorWall)
                : anchorTime
            if !advancing || abs(displayedNow - new) > 0.35 {
                // seek、切歌、暂停恢复或漂移超限：媒体时间与墙钟脱钩，整体重同步。
                anchorTime = new
                anchorWall = wallNow
            } else {
                // 正常推进：锚点墙钟按媒体时间走，投递延迟不进显示。
                anchorTime = new
                anchorWall = anchorWall.addingTimeInterval(clockDelta)
            }
        }
    }
}

/// Apple Music 风格的平滑进度条。
///
/// 进度由 TimelineView 按帧插值后传入，这里不做任何进度动画，绘制即所见；
/// 拖动时本地覆盖显示值并实时跟手，松手才 seek。
private struct SmoothScrubber: View {
    let progress: Double
    let duration: Double
    let isEnabled: Bool
    let seek: (Double) -> Void

    @State private var dragTime: Double?
    @State private var isHovering = false

    private var displayProgress: Double {
        if let dragTime {
            return duration > 0 ? min(max(dragTime / duration, 0), 1) : 0
        }
        return progress
    }
    private var isDragging: Bool { dragTime != nil }
    private var showKnob: Bool { isHovering || isDragging }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = min(max(width * displayProgress - 5.5, -1), width - 10)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.hpTextPrimary.opacity(0.15))
                    .frame(height: 3.5)
                Capsule()
                    .fill(Color.hpAccent)
                    .frame(width: max(3.5, width * displayProgress), height: 3.5)
                Circle()
                    .fill(Color.hpAccent)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.22), radius: 1.6, y: 0.5)
                    .scaleEffect(showKnob ? 1 : 0.5)
                    .opacity(showKnob ? 1 : 0)
                    // 出现/消失动画只作用在缩放与透明度上；位置不参与这次
                    // 动画，因此小球出现时直接就在当前播放位置，不会从
                    // 上次消失的地方滑过来。
                    .animation(.easeInOut(duration: 0.16), value: showKnob)
                    .offset(x: knobX)
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(dragGesture(width))
        }
        .frame(height: 13)
    }

    private func dragGesture(_ width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                let ratio = min(max(value.location.x / max(width, 1), 0), 1)
                dragTime = ratio * duration
            }
            .onEnded { _ in
                guard let target = dragTime else { return }
                dragTime = nil
                seek(target)
            }
    }
}

/// Sleep-timer countdown. Observing `PlaybackClock` here keeps the once-per-
/// second countdown from invalidating the rest of the player bar.
struct SleepTimerLabel: View {
    @ObservedObject var clock: PlaybackClock
    let isActive: Bool

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: isActive ? "moon.zzz.fill" : "moon.zzz")
                .font(.system(size: 10, weight: .semibold))
            if let remaining = clock.sleepTimerRemaining {
                Text(Self.shortRemaining(remaining))
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
            }
        }
        .foregroundStyle(isActive ? Color.hpAccent : Color.hpTextPrimary.opacity(0.44))
        .frame(width: 34, height: 28)
    }

    private static func shortRemaining(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(ceil(seconds / 60)))
        return "\(minutes)m"
    }
}

/// Play/pause glyph with a light symbol swap. Falls back to an instant swap
/// when the user asks for reduced motion.
struct PlaybackToggleSymbol: View {
    let isPlaying: Bool
    let size: CGFloat
    var offsetWhenPaused: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: isPlaying ? 0 : offsetWhenPaused)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isPlaying)
    }
}

/// Subtle press feedback for the round transport buttons. `reduceMotion` is
/// passed in by the owning view, because a `ButtonStyle` is not a dynamic
/// property container.
struct PlaybackPressButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

/// 浮出式音量控件（播放页控制行用）：点击喇叭从**右方**弹出横向滑块、
/// 再点收起；收起时悬停滚轮调音量；滑块悬浮、不挤占按钮行布局；展开
/// 期间点击热区之外自动收起（NSEvent 本地监视器，事件原样放行）。
/// 滚轮调节同样走 NSEvent 本地监视器——不用 NSView 捕获层：原生视图盖在
/// 图标上方时会成为 SwiftUI 命中测试的终点，图标自身的手势失效，点击会
/// 漏给祖先容器。依赖的 VolumeFrameReporter 与 HorizontalVolumeSlider
/// 定义在 NowPlayingView.swift。
struct PlayerVolumeControl: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var showsVolumeSlider = false
    /// 滑块共享状态（引用类型）：NSEvent 监视器闭包从 @State 读到的是旧快照，
    /// 必须经由 class 引用才能保证监视器始终读到最新的展开状态与热区位置。
    private final class VolumeDismissState {
        var isExpanded = false
        var hotFrame: CGRect?
    }
    @State private var volumeState = VolumeDismissState()
    @State private var volumeDismissMonitor: Any?
    @State private var volumeScrollMonitor: Any?

    var body: some View {
        Image(systemName: volumeIconName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .background(VolumeFrameReporter { volumeState.hotFrame = $0 })
            .overlay(alignment: .bottom) {
                Text("\(Int((player.volume * 100).rounded()))")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .offset(y: 5)
                    .opacity(showsVolumeSlider ? 0 : 1)
            }
            .overlay(alignment: .leading) {
                HorizontalVolumeSlider(value: Binding(
                    get: { player.volume },
                    set: { player.volume = $0 }
                ))
                .scaleEffect(x: showsVolumeSlider ? 1 : 0.4, anchor: .leading)
                .opacity(showsVolumeSlider ? 1 : 0)
                .offset(x: showsVolumeSlider ? 32 : 40)
                .allowsHitTesting(showsVolumeSlider)
            }
            .onTapGesture {
                // 点击喇叭切换展开/收起。滚轮捕获层已移除，SwiftUI 命中测试
                // 直达图标，内层手势优先于祖先层。
                volumeState.isExpanded = !showsVolumeSlider
                withAnimation(.easeInOut(duration: 0.24)) {
                    showsVolumeSlider.toggle()
                }
            }
            .help("点击展开/收起音量滑块；收起时悬停滚动可调音量")
            .onAppear { installMonitors() }
            .onDisappear { removeMonitors() }
    }

    private var volumeIconName: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private func installMonitors() {
        guard volumeDismissMonitor == nil else { return }

        // 点击外部收起：热区外左键按下即收起，事件原样放行。
        volumeDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if volumeState.isExpanded {
                let insideHotZone = hotZone()?.contains(event.locationInWindow) ?? false
                if !insideHotZone {
                    volumeState.isExpanded = false
                    withAnimation(.easeInOut(duration: 0.24)) {
                        showsVolumeSlider = false
                    }
                }
            }
            return event
        }

        // 悬停滚轮调音量：仅收起时、仅悬停在喇叭上时吞掉事件，
        // 其余情况原样放行（不影响背后列表的正常滚动）。
        volumeScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if !showsVolumeSlider,
               event.scrollingDeltaY != 0,
               volumeState.hotFrame?.contains(event.locationInWindow) == true {
                let delta = -event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 40 : 8)
                let clamped = min(0.15, max(-0.15, delta))
                player.volume = min(1, max(0, player.volume + clamped))
                return nil
            }
            return event
        }
    }

    /// 滑块热区：向右扩展（横向滑块浮层所在区域）。
    private func hotZone() -> CGRect? {
        volumeState.hotFrame.map { icon in
            CGRect(x: icon.minX, y: icon.minY, width: icon.width + 70, height: icon.height)
        }
    }

    private func removeMonitors() {
        if let monitor = volumeDismissMonitor {
            NSEvent.removeMonitor(monitor)
            volumeDismissMonitor = nil
        }
        if let monitor = volumeScrollMonitor {
            NSEvent.removeMonitor(monitor)
            volumeScrollMonitor = nil
        }
    }
}

/// 播放条音量控件：喇叭（下方音量数字）+ 右侧常驻横向滑条，
/// 点击轨道跳转、按住拖动调节；悬停滚轮同样可调（NSEvent 监视器按
/// 控件窗口坐标判断，事件吞掉、不影响背后列表滚动）。
struct BarVolumeControl: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var controlFrame: CGRect?
    @State private var volumeScrollMonitor: Any?
    /// 静音前记忆的音量（仅会话内有效）：再次点击喇叭时恢复。
    @State private var preMuteVolume: Double?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: volumeIconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 点击喇叭：静音 / 取消静音（记住静音前的音量）。
                    // 图标自带手势后内层优先于祖先层，不会误触"进播放页"。
                    if player.volume > 0 {
                        preMuteVolume = player.volume
                        player.volume = 0
                    } else if let restored = preMuteVolume, restored > 0 {
                        player.volume = restored
                        preMuteVolume = nil
                    }
                }
                .overlay(alignment: .bottom) {
                    Text("\(Int((player.volume * 100).rounded()))")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                        .offset(y: 5)
                }

            HorizontalVolumeSlider(value: Binding(
                get: { player.volume },
                set: { player.volume = $0 }
            ))
        }
        .background(VolumeFrameReporter { controlFrame = $0 })
        .help("点击喇叭静音/取消静音；拖动滑条或悬停滚轮调整音量")
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
    }

    private var volumeIconName: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    private func installScrollMonitor() {
        guard volumeScrollMonitor == nil else { return }
        volumeScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.scrollingDeltaY != 0,
               controlFrame?.contains(event.locationInWindow) == true {
                let delta = -event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 40 : 8)
                let clamped = min(0.15, max(-0.15, delta))
                player.volume = min(1, max(0, player.volume + clamped))
                return nil
            }
            return event
        }
    }

    private func removeScrollMonitor() {
        if let monitor = volumeScrollMonitor {
            NSEvent.removeMonitor(monitor)
            volumeScrollMonitor = nil
        }
    }
}
