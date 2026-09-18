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
            nowPlaying
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
        HStack(spacing: 12) {
            nowPlaying
                .frame(maxWidth: .infinity, alignment: .leading)

            controls
                .frame(minWidth: 270, idealWidth: 320, maxWidth: 350)

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
                    ArtworkView(image: player.artwork, size: 44, cornerRadius: 10)
                        .matchedGeometryEffect(id: "nowPlayingArtwork.playerBar", in: transitionNamespace, isSource: true)

                    if let track = player.currentTrack {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.displayTitle)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.hpTextPrimary)
                                    .lineLimit(1)
                                Text(track.displayArtist)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.hpTextPrimary.opacity(0.44))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            formatBadge(for: track)
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
                        .frame(width: 26, height: 26)
                        .overlay(alignment: .bottom) {
                            Circle()
                                .fill(Color.hpAccent)
                                .frame(width: 3.5, height: 3.5)
                                .offset(y: 2.5)
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
                    help: (player.currentTrack.flatMap { library.isFavorite($0) } ?? false) ? "取消收藏" : "收藏",
                    size: 13
                ) {
                    if let track = player.currentTrack {
                        library.toggleFavorite(track)
                    }
                }
                .disabled(player.currentTrack == nil)
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
        Text(track.url.pathExtension.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.hpAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.hpAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
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
            sleepTimerMenu

            // 简化版音量控件：喇叭 + 下方数字（不带%）+ 悬停滚轮调音量。
            ZStack {
                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                    .frame(width: 28, height: 28)

                Text("\(Int((player.volume * 100).rounded()))")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .offset(y: 5)

                VolumeScrollCatcher { delta in
                    let clamped = min(0.15, max(-0.15, delta))
                    player.volume = min(1, max(0, player.volume + clamped))
                }
            }
            .frame(width: 28)
            .help("悬停滚轮调整音量")

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
            sleepTimerMenu

            Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.44))
                .frame(width: 18)

            Slider(value: $player.volume, in: 0...1)
                .controlSize(.mini)
                .frame(width: 76)
                .tint(.hpAccent)

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
