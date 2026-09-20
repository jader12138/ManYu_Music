import SwiftUI

/// 菜单栏弹出的迷你播放器：封面、歌曲信息、当前/下一句歌词、进度条与
/// 上一首/播放暂停/下一首。与主播放条共用同一套控件与主题色。
struct MiniPlayerView: View {
    @ObservedObject var player: AudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasTrack: Bool { player.currentTrack != nil }

    var body: some View {
        VStack(spacing: 12) {
            header
            lyricBlock
            PlaybackProgressRow(
                clock: player.clock,
                isEnabled: hasTrack,
                seek: player.seek,
                isPlaying: player.isPlaying,
                isRapidSwitching: player.isRapidSwitching
            )
            transport
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - 歌曲信息

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(
                image: player.artwork,
                size: 56,
                cornerRadius: ArtworkLayout.cornerRadius(for: 56)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.displayTitle ?? "未在播放")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    /// 歌手 · 专辑；专辑未填写时只显示歌手，无曲目时留空占位。
    private var subtitle: String {
        guard let track = player.currentTrack else { return " " }
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return album.isEmpty ? track.displayArtist : "\(track.displayArtist) · \(track.displayAlbum)"
    }

    // MARK: - 歌词

    /// 当前句加预览下一句；两行高度固定，避免歌词切换时面板高度跳动。
    private var lyricBlock: some View {
        VStack(spacing: 4) {
            Text(player.currentLyricText ?? "暂无歌词")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
                .frame(maxWidth: .infinity)

            Text(player.nextLyricText ?? " ")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.hpTextSecondary.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(height: 14)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 7)
        .background(
            Color.hpTextPrimary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: HPMetrics.radiusRow, style: .continuous)
        )
    }

    // MARK: - 控制

    private var transport: some View {
        HStack(spacing: 24) {
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
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.hpAccent.opacity(0.24), radius: 7, y: 3)
                    PlaybackToggleSymbol(isPlaying: player.isPlaying, size: 13, offsetWhenPaused: 1)
                }
            }
            .buttonStyle(PlaybackPressButtonStyle(reduceMotion: reduceMotion))
            .disabled(!hasTrack)
            .help(player.isPlaying ? "暂停" : "播放")

            IconButton(systemName: "forward.fill", help: "下一首", size: 15) {
                player.next()
            }
            .disabled(player.queue.isEmpty)
        }
        .frame(maxWidth: .infinity)
    }
}
