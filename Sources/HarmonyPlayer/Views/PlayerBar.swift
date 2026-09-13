import AppKit
import SwiftUI

struct PlayerBar: View {
    @Binding var showQueue: Bool
    @Binding var showNowPlaying: Bool
    let transitionNamespace: Namespace.ID

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var scrubTime: Double?
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
            VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                .overlay(Color.hpNavyDeep.opacity(0.76))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.hpTextPrimary.opacity(0.08))
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
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
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

            HStack(spacing: 8) {
                Text(Track.formatTime(scrubTime ?? player.currentTime))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                    .frame(width: 40, alignment: .trailing)

                Slider(
                    value: playbackBinding,
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { isEditing in
                        guard !isEditing, let scrubTime else { return }
                        player.seek(to: scrubTime)
                        self.scrubTime = nil
                    }
                )
                .controlSize(.mini)
                .tint(.hpAccent)
                .disabled(player.currentTrack == nil)

                Text(player.duration > 0 ? Track.formatTime(player.duration) : "--:--")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                    .frame(width: 40, alignment: .leading)
            }
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
            VStack(spacing: 1) {
                Image(systemName: player.sleepTimerEnd == nil ? "moon.zzz" : "moon.zzz.fill")
                    .font(.system(size: 10, weight: .semibold))
                if let remaining = player.sleepTimerRemaining {
                    Text(shortRemaining(remaining))
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                }
            }
            .foregroundStyle(player.sleepTimerEnd == nil ? Color.hpTextPrimary.opacity(0.44) : Color.hpAccent)
            .frame(width: 34, height: 28)
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

    private var playbackBinding: Binding<Double> {
        Binding(
            get: {
                let time = scrubTime ?? player.currentTime
                return min(time, max(player.duration, time))
            },
            set: { scrubTime = $0 }
        )
    }

    private func shortRemaining(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(ceil(seconds / 60)))
        return "\(minutes)m"
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
