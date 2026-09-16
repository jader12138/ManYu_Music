import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    let back: () -> Void
    let onPlay: (Track, [Track]) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer

    @State private var showingRename = false

    private var tracks: [Track] {
        library.tracks(in: playlist)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                Divider().opacity(0.18)

                if tracks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.28))
                        Text("歌单中还没有歌曲")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.64))
                        Text("在歌曲的右键菜单里选择“添加到歌单”")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.36))
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(tracks) { track in
                            TrackRow(
                                track: track,
                                isCurrent: player.currentTrack?.id == track.id,
                                isPlaying: player.isPlaying,
                                isFavorite: library.isFavorite(track),
                                play: { onPlay(track, tracks) },
                                toggleFavorite: { library.toggleFavorite(track) },
                                reveal: { library.reveal(track) },
                                remove: { library.remove(track, from: playlist.id) },
                                removeLabel: "从歌单移除"
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
        .sheet(isPresented: $showingRename) {
            PlaylistNameEditor(
                title: "重命名歌单",
                placeholder: "歌单名称",
                initialName: playlist.name
            ) { name in
                library.renamePlaylist(playlist, to: name)
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 26) {
            playlistArtwork

            VStack(alignment: .leading, spacing: 10) {
                Text("歌单")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.hpAccent)
                    .tracking(1.4)

                Text(playlist.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(2)

                Text("\(tracks.count) 首歌曲  ·  \(Track.formatTime(tracks.reduce(0) { $0 + $1.duration }))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))

                HStack(spacing: 10) {
                    Button {
                        if let first = tracks.first {
                            onPlay(first, tracks)
                        }
                    } label: {
                        Label("播放", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 17)
                            .frame(height: 36)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(AccentFillButtonStyle())
                    .disabled(tracks.isEmpty)

                    Button {
                        showingRename = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.72))
                    }
                    .buttonStyle(HoverHighlightButtonStyle())

                    Button(action: back) {
                        Label("返回", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.72))
                    }
                    .buttonStyle(HoverHighlightButtonStyle())

                    Button(role: .destructive) {
                        library.deletePlaylist(playlist)
                        back()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(Color.hpPink)
                    }
                    .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 18))
                    .help("删除歌单")
                }
            }

            Spacer()
        }
    }

    private var playlistArtwork: some View {
        Group {
            if let track = tracks.first {
                LazyArtworkView(track: track, size: 196, cornerRadius: 16)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient.hpBrandFill)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 196, height: 196)
                .shadow(color: Color.hpAccent.opacity(0.22), radius: 16, y: 8)
            }
        }
    }
}
