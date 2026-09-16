import AppKit
import SwiftUI

struct PlayerBar: View {
    @Binding var showQueue: Bool
    @Binding var showNowPlaying: Bool
    let transitionNamespace: Namespace.ID

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
                    showNowPlaying.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ArtworkView(image: player.artwork, size: 44, cornerRadius: 10)
                        .matchedGeometryEffect(id: "nowPlayingArtwork", in: transitionNamespace)

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
            .buttonStyle(.plain)
            .disabled(player.currentTrack == nil)

            if let track = player.currentTrack {
                Button {
                    library.toggleFavorite(track)
                } label: {
                    Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(library.isFavorite(track) ? Color.hpPink : Color.hpTextPrimary.opacity(0.42))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 5) {
            HStack(spacing: 15) {
                IconButton(
                    systemName: "shuffle",
                    isActive: player.isShuffle,
                    help: player.isShuffle ? "关闭随机播放" : "随机播放",
                    size: 13
                ) {
                    player.isShuffle.toggle()
                }

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

                IconButton(systemName: "forward.fill", help: "下一首", size: 15) {
                    player.next()
                }
                .disabled(player.queue.isEmpty)

                IconButton(
                    systemName: player.repeatMode.systemImage,
                    isActive: player.repeatMode.isActive,
                    help: repeatHelp,
                    size: 13
                ) {
                    player.repeatMode.advance()
                }
            }

            PlaybackProgressRow(
                clock: player.clock,
                isEnabled: player.currentTrack != nil,
                seek: player.seek
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

            Menu {
                Button("静音") { player.volume = 0 }
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                    Button("\(Int(value * 100))%") { player.volume = value }
                }
            } label: {
                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)

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

    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: "开启列表循环"
        case .all: "切换为单曲循环"
        case .one: "关闭循环"
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
    var controlSize: ControlSize = .mini
    var fontWeight: Font.Weight = .medium

    var body: some View {
        HStack(spacing: 8) {
            Text(Track.formatTime(clock.currentTime))
                .font(.system(size: 9, weight: fontWeight, design: .monospaced))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                .frame(width: 40, alignment: .trailing)

            SmoothScrubber(
                time: clock.currentTime,
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
}

/// Apple Music 风格的平滑进度条。
///
/// 时钟每 0.25s 才更新一次进度，系统 Slider 会一格一格地跳；这里把进度值
/// 挂上缓动动画，让相邻两次更新连成连续的滑行。拖动时关闭缓动，保证跟手。
private struct SmoothScrubber: View {
    let time: Double
    let duration: Double
    let isEnabled: Bool
    let seek: (Double) -> Void

    @State private var dragTime: Double?
    @State private var isHovering = false

    private var progress: Double {
        let current = dragTime ?? time
        return duration > 0 ? min(max(current / duration, 0), 1) : 0
    }
    private var isDragging: Bool { dragTime != nil }
    private var showKnob: Bool { isHovering || isDragging }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = min(max(width * progress - 5.5, -1), width - 10)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.hpTextPrimary.opacity(0.15))
                    .frame(height: 3.5)
                Capsule()
                    .fill(Color.hpAccent)
                    .frame(width: max(3.5, width * progress), height: 3.5)
                Circle()
                    .fill(Color.hpAccent)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.22), radius: 1.6, y: 0.5)
                    .offset(x: knobX)
                    .opacity(showKnob ? 1 : 0)
                    .scaleEffect(showKnob ? 1 : 0.5)
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .animation(isDragging ? nil : .easeInOut(duration: 0.45), value: progress)
            .animation(.easeInOut(duration: 0.16), value: showKnob)
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
                seek(target)
                dragTime = nil
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
