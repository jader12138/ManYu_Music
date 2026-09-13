import SwiftUI

struct HomeView: View {
    let tracks: [Track]
    let albums: [AlbumGroup]
    let recentTracks: [Track]
    let favoriteTracks: [Track]
    let openAlbum: (AlbumGroup) -> Void

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var loadedFeaturedLyrics: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                hero
                quickActions

                if !recentTracks.isEmpty {
                    mediaSection(title: "最近播放", subtitle: "继续上次的音乐旅程") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(recentTracks.prefix(10)) { track in
                                    HomeTrackCard(track: track) {
                                        play(track, in: recentTracks)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !albums.isEmpty {
                    mediaSection(title: "最近添加", subtitle: "资料库里的新声音") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 18) {
                                ForEach(albums.prefix(10)) { album in
                                    HomeAlbumCard(album: album) {
                                        openAlbum(album)
                                    } play: {
                                        guard let first = album.tracks.first else { return }
                                        play(first, in: album.tracks)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !favoriteTracks.isEmpty {
                    mediaSection(title: "我喜欢的音乐", subtitle: "\(favoriteTracks.count) 首收藏") {
                        VStack(spacing: 2) {
                            ForEach(favoriteTracks.prefix(6)) { track in
                                TrackRow(
                                    track: track,
                                    isCurrent: player.currentTrack?.id == track.id,
                                    isPlaying: player.isPlaying,
                                    isFavorite: true,
                                    play: { play(track, in: favoriteTracks) },
                                    toggleFavorite: { library.toggleFavorite(track) },
                                    reveal: { library.reveal(track) },
                                    remove: { library.remove(track) }
                                )
                            }
                        }
                    }
                }

                if tracks.isEmpty {
                    EmptyLibraryView(
                        isSearching: false,
                        isDropTargeted: false,
                        importAction: library.presentImportPanel
                    )
                    .frame(minHeight: 280)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .task(id: featuredTrack?.id) {
            guard let track = featuredTrack else {
                loadedFeaturedLyrics = []
                return
            }

            if player.currentTrack?.id == track.id, !player.lyricLines.isEmpty {
                loadedFeaturedLyrics = []
                return
            }

            let rawLyrics = await AudioMetadataLoader.lyrics(for: track)
            let lines = LyricsParser.parse(rawLyrics)
                .filter { line in
                    !line.text.isEmpty
                        && !line.text.contains("词：")
                        && !line.text.contains("曲：")
                }
            loadedFeaturedLyrics = Array(lines.dropFirst(2).prefix(4).map(\.text))
        }
    }

    private var hero: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text(greeting)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)

                Text(heroSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.58))

                lyricExcerpt
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = featuredTrack {
                ZStack(alignment: .bottomTrailing) {
                    LazyArtworkView(track: track, size: 184, cornerRadius: 20)

                    PlaybackStateBadge(
                        isPlaying: player.isPlaying && player.currentTrack?.id == track.id,
                        size: 30
                    )
                    .padding(10)
                }
            } else {
                ArtworkView(image: nil, size: 184, cornerRadius: 20)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.hpSurface.opacity(0.86), Color.hpAccent.opacity(0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.hpTextPrimary.opacity(0.07), lineWidth: 1)
        }
    }

    private var lyricExcerpt: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(LinearGradient.hpAccentFill)
                .frame(width: 3)
                .frame(minHeight: 58, maxHeight: 120)

            Text(lyricPassageText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.78))
                .lineSpacing(6)
                .lineLimit(3...4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                if let first = tracks.first {
                    play(first, in: tracks)
                }
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 17)
                    .frame(height: 38)
                    .foregroundStyle(.white)
                    .background(LinearGradient.hpAccentFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)

            Button {
                player.isShuffle = true
                if let random = tracks.randomElement() {
                    play(random, in: tracks)
                }
            } label: {
                Label("随机播放", systemImage: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.78))
                    .background(Color.hpTextPrimary.opacity(0.065), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)

            Spacer()

            Label("\(tracks.count) 首歌曲", systemImage: "music.note")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
        }
    }

    private func mediaSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                Spacer()
            }

            content()
        }
    }

    private func play(_ track: Track, in list: [Track]) {
        if player.currentTrack?.id == track.id {
            player.togglePlayback()
        } else {
            player.play(track, in: list)
        }
    }

    private var featuredTrack: Track? {
        player.currentTrack ?? recentTracks.first ?? favoriteTracks.first ?? tracks.first
    }

    private var lyricPassage: [String] {
        if featuredTrack?.id == player.currentTrack?.id {
            let passage = player.lyricPassage(maxLines: 4)
            if !passage.isEmpty { return passage }
        }
        if !loadedFeaturedLyrics.isEmpty {
            return loadedFeaturedLyrics
        }
        if let track = featuredTrack {
            return ["正在播放：\(track.displayTitle)"]
        }
        return ["让每一次播放都留在自己的音乐宇宙里"]
    }

    private var lyricPassageText: String {
        lyricPassage.prefix(4).joined(separator: "\n")
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var heroSubtitle: String {
        if tracks.isEmpty {
            return "先导入一些音乐，开始打造属于你的漫域"
        }
        return "你的音乐宇宙里有 \(tracks.count) 首歌曲、\(Set(tracks.map(\.displayAlbum)).count) 张专辑"
    }
}

private struct HomeTrackCard: View {
    let track: Track
    let play: () -> Void

    @EnvironmentObject private var player: AudioPlayer
    @State private var isHovering = false

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    LazyArtworkView(track: track, size: 136, cornerRadius: 14)
                    if isHovering {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.28))
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(LinearGradient.hpAccentFill, in: Circle())
                    }
                }

                Text(track.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .lineLimit(1)
            }
            .frame(width: 136, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HomeAlbumCard: View {
    let album: AlbumGroup
    let open: () -> Void
    let play: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                if let track = album.artworkTrack {
                    LazyArtworkView(track: track, size: 146, cornerRadius: 14)
                } else {
                    ArtworkView(image: nil, size: 146, cornerRadius: 14)
                }

                if isHovering {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.black.opacity(0.27))
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(LinearGradient.hpAccentFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 146, height: 146)
            .onTapGesture(perform: open)

            Text(album.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                .lineLimit(1)
            Text(album.artist)
                .font(.system(size: 9))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                .lineLimit(1)
        }
        .frame(width: 146, alignment: .leading)
        .onHover { isHovering = $0 }
    }
}
