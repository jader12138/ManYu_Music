import SwiftUI

struct TrackListView: View {
    let tracks: [Track]
    var showsHeader = true
    let onPlay: (Track) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider().opacity(0.18)
            }

            List {
                ForEach(tracks) { track in
                    TrackRow(
                        track: track,
                        isCurrent: player.currentTrack?.id == track.id,
                        isPlaying: player.isPlaying,
                        isFavorite: library.isFavorite(track),
                        play: { onPlay(track) },
                        toggleFavorite: { library.toggleFavorite(track) },
                        reveal: { library.reveal(track) },
                        remove: { library.remove(track) }
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.top, -140)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 44)
            Text("标题")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("专辑")
                .frame(width: 170, alignment: .leading)
            Text("时长")
                .frame(width: 48, alignment: .trailing)
            Color.clear.frame(width: 72)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.hpTextPrimary.opacity(0.36))
        .tracking(0.45)
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let play: () -> Void
    let toggleFavorite: () -> Void
    let reveal: () -> Void
    let remove: () -> Void
    var removeLabel = "从资料库移除"

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var playerStore: AudioPlayer
    @State private var isHovering = false
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                LazyArtworkView(track: track, size: 44, cornerRadius: 9)

                if isCurrent || isHovering {
                    PlaybackStateBadge(
                        isPlaying: isCurrent && isPlaying,
                        size: 22
                    )
                    .padding(2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Color.hpAccent : Color.hpTextPrimary.opacity(0.94))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.url.pathExtension.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.hpAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.hpAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 3))
                    Text(track.displayArtist)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.displayAlbum)
                .font(.system(size: 11))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Text(track.formattedDuration)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                .frame(width: 48, alignment: .trailing)

            HStack(spacing: 2) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isFavorite ? Color.hpPink : Color.hpTextPrimary.opacity(0.38))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("播放", action: play)
                    Button(isFavorite ? "取消收藏" : "收藏", action: toggleFavorite)
                    Button("下一首播放") {
                        playerStore.playNext(track)
                    }
                    Button("添加到播放队列") {
                        playerStore.addToQueue(track)
                    }

                    if !libraryStore.playlists.isEmpty {
                        Menu("添加到歌单") {
                            ForEach(libraryStore.playlists) { playlist in
                                Button(playlist.name) {
                                    libraryStore.add(track, to: playlist.id)
                                }
                            }
                        }
                    }

                    Button("显示歌曲信息") {
                        showingInfo = true
                    }

                    Button("在访达中显示", action: reveal)
                    Divider()
                    Button(role: .destructive, action: remove) {
                        Label(removeLabel, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
            .frame(width: 72)
        }
        .padding(.horizontal, 12)
        .frame(height: 61)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        }
        .overlay(alignment: .leading) {
            if isCurrent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.hpAccent)
                    .frame(width: 3, height: 28)
                    .offset(x: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture(perform: play)
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showingInfo) {
            TrackInfoView(track: track)
                .environmentObject(libraryStore)
        }
        .contextMenu {
            Button("播放", action: play)
            Button(isFavorite ? "取消收藏" : "收藏", action: toggleFavorite)
            Button("下一首播放") {
                playerStore.playNext(track)
            }
            Button("添加到播放队列") {
                playerStore.addToQueue(track)
            }

            if !libraryStore.playlists.isEmpty {
                Menu("添加到歌单") {
                    ForEach(libraryStore.playlists) { playlist in
                        Button(playlist.name) {
                            libraryStore.add(track, to: playlist.id)
                        }
                    }
                }
            }

            Button("显示歌曲信息") {
                showingInfo = true
            }

            Button("在访达中显示", action: reveal)
            Divider()
            Button(role: .destructive, action: remove) {
                Label(removeLabel, systemImage: "trash")
            }
        }
    }

    private var rowBackground: AnyShapeStyle {
        if isCurrent {
            return AnyShapeStyle(LinearGradient.hpSelectedRow)
        }
        if isHovering {
            return AnyShapeStyle(Color.hpTextPrimary.opacity(0.045))
        }
        return AnyShapeStyle(Color.clear)
    }
}

struct AlbumGridView: View {
    let albums: [AlbumGroup]
    let onOpen: (AlbumGroup) -> Void
    let onPlay: (AlbumGroup) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 178), spacing: 22, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(albums) { album in
                    AlbumCard(
                        album: album,
                        open: { onOpen(album) },
                        play: { onPlay(album) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

private struct AlbumCard: View {
    let album: AlbumGroup
    let open: () -> Void
    let play: () -> Void

    @EnvironmentObject private var player: AudioPlayer
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let track = album.artworkTrack {
                    LazyArtworkView(track: track, size: 156, cornerRadius: 13)
                } else {
                    ArtworkView(image: nil, size: 156, cornerRadius: 13)
                }

                if isHovering {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.black.opacity(0.30))
                }

                if isHovering {
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.hpNavyDeep)
                            .frame(width: 46, height: 46)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                }

                if let track = album.artworkTrack,
                   player.currentTrack?.displayAlbum == track.displayAlbum {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.hpAccent)
                                .frame(width: 8, height: 8)
                                .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 156, height: 156)
            .scaleEffect(isHovering ? 1.018 : 1)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onTapGesture(perform: open)

            Text(album.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                .lineLimit(1)

            Text(album.artist)
                .font(.system(size: 10))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
                .lineLimit(1)
        }
        .frame(width: 156, alignment: .leading)
        .onHover { isHovering = $0 }
    }
}

struct AlbumDetailView: View {
    let album: AlbumGroup
    let back: () -> Void
    let onPlay: (Track, [Track]) -> Void

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                Divider().opacity(0.18)

                LazyVStack(spacing: 2) {
                    ForEach(album.tracks) { track in
                        TrackRow(
                            track: track,
                            isCurrent: player.currentTrack?.id == track.id,
                            isPlaying: player.isPlaying,
                            isFavorite: library.isFavorite(track),
                            play: { onPlay(track, album.tracks) },
                            toggleFavorite: { library.toggleFavorite(track) },
                            reveal: { library.reveal(track) },
                            remove: { library.remove(track) }
                        )
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 26) {
            if let track = album.artworkTrack {
                LazyArtworkView(track: track, size: 196, cornerRadius: 16)
            } else {
                ArtworkView(image: nil, size: 196, cornerRadius: 16)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("专辑")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.hpAccent)
                    .tracking(1.4)

                Text(album.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(2)

                Text(album.artist)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.72))

                Text("\(album.tracks.count) 首歌曲  ·  \(Track.formatTime(album.duration))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))

                HStack(spacing: 10) {
                    Button {
                        if let first = album.tracks.first {
                            onPlay(first, album.tracks)
                        }
                    } label: {
                        Label("播放专辑", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .foregroundStyle(.white)
                            .background(LinearGradient.hpAccentFill, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: back) {
                        Label("返回", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.72))
                            .background(Color.hpTextPrimary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }
}

struct ArtistGridView: View {
    let artists: [ArtistGroup]
    let onOpen: (ArtistGroup) -> Void
    let onPlay: (ArtistGroup) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 174), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(artists) { artist in
                    ArtistCard(
                        artist: artist,
                        open: { onOpen(artist) },
                        play: { onPlay(artist) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }
}

private struct ArtistCard: View {
    let artist: ArtistGroup
    let open: () -> Void
    let play: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                if let track = artist.artworkTrack {
                    LazyArtworkView(track: track, size: 138, cornerRadius: 69)
                } else {
                    ArtworkView(image: nil, size: 138, cornerRadius: 69)
                }

                if isHovering {
                    Circle()
                        .fill(.black.opacity(0.30))
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(LinearGradient.hpAccentFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 138, height: 138)
            .onTapGesture(perform: open)

            VStack(spacing: 3) {
                Text(artist.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                    .lineLimit(1)
                Text("\(artist.tracks.count) 首歌曲 · \(artist.albumCount) 张专辑")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            isHovering ? Color.hpTextPrimary.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onHover { isHovering = $0 }
    }
}

struct ArtistDetailView: View {
    let artist: ArtistGroup
    let back: () -> Void
    let onPlay: (Track, [Track]) -> Void

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                Divider().opacity(0.18)

                LazyVStack(spacing: 2) {
                    ForEach(artist.tracks) { track in
                        TrackRow(
                            track: track,
                            isCurrent: player.currentTrack?.id == track.id,
                            isPlaying: player.isPlaying,
                            isFavorite: library.isFavorite(track),
                            play: { onPlay(track, artist.tracks) },
                            toggleFavorite: { library.toggleFavorite(track) },
                            reveal: { library.reveal(track) },
                            remove: { library.remove(track) }
                        )
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 26) {
            if let track = artist.artworkTrack {
                LazyArtworkView(track: track, size: 190, cornerRadius: 95)
            } else {
                ArtworkView(image: nil, size: 190, cornerRadius: 95)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("艺术家")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.hpAccent)
                    .tracking(1.4)

                Text(artist.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(2)

                Text("\(artist.tracks.count) 首歌曲 · \(artist.albumCount) 张专辑")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))

                HStack(spacing: 10) {
                    Button {
                        if let first = artist.tracks.first {
                            onPlay(first, artist.tracks)
                        }
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 17)
                            .frame(height: 36)
                            .foregroundStyle(.white)
                            .background(LinearGradient.hpAccentFill, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: back) {
                        Label("返回", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.72))
                            .background(Color.hpTextPrimary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }
}

struct EmptyLibraryView: View {
    let isSearching: Bool
    let isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.hpAccent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: isSearching ? "magnifyingglass" : "waveform")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.hpAccent)
            }

            VStack(spacing: 7) {
                Text(isSearching ? "没有找到相关音乐" : (isDropTargeted ? "松开即可导入" : "漫域音乐，从一首歌开始"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text(isSearching ? "换个关键词试试" : "支持 MP3、M4A、AAC、FLAC、WAV、AIFF 等格式")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
            }

            if !isSearching {
                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Label("前往设置添加音乐", systemImage: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(LinearGradient.hpAccentFill, in: Capsule())
                }
                .buttonStyle(.plain)

                Text("也可以在设置中导入文件夹")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.32))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
