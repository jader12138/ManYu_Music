import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var theme: ThemeStore

    @State private var destination: LibraryDestination = .section(.home)
    @State private var selectedAlbum: AlbumGroup?
    @State private var selectedArtist: ArtistGroup?
    @State private var searchText = ""
    @State private var showQueue = false
    @State private var showNowPlaying = false
    @State private var isDropTargeted = false
    @State private var sortOrder: TrackSortOrder = .dateAdded
    @State private var sortAscending = false
    @Namespace private var nowPlayingTransition
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            if showNowPlaying {
                NowPlayingView(transitionNamespace: nowPlayingTransition)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .background {
                    NowPlayingBackdrop()
                        .ignoresSafeArea(.container, edges: .top)
                }
                .overlay(alignment: .topLeading) {
                    NowPlayingHeaderControls {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            showNowPlaying = false
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 16)
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        SidebarView(destination: $destination)

                        detail
                            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                        if showQueue {
                            Rectangle()
                                .fill(Color.hpTextPrimary.opacity(0.07))
                                .frame(width: 1)
                            QueuePanel {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showQueue = false
                                }
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(height: max(0, geometry.size.height - 72))

                    PlayerBar(
                        showQueue: $showQueue,
                        showNowPlaying: $showNowPlaying,
                        transitionNamespace: nowPlayingTransition
                    )
                        .frame(width: geometry.size.width, height: 72)
                }
            }
        }
        .background(AppBackground())
        .frame(minWidth: 860, minHeight: 540)
        .overlay(alignment: .top) {
            if !showNowPlaying {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 238)
                    Color.hpNavy.opacity(0.28)
                }
                .frame(height: 30)
                .offset(y: -30)
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            library.add(urls: urls)
            return true
        } isTargeted: { isTargeted in
            withAnimation(.easeOut(duration: 0.16)) {
                isDropTargeted = isTargeted
            }
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .overlay(alignment: .top) {
            if let notice = library.importNotice {
                NoticeView(message: notice)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: library.importNotice)
        .onAppear {
            searchIsFocused = false
            player.restorePlaybackState(from: library.tracks)
            updateWindowBackground()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                searchIsFocused = false
            }
        }
        .onChange(of: showNowPlaying) { _, _ in
            updateWindowBackground()
        }
        .onReceive(player.$artworkPalette) { _ in
            updateWindowBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLibrarySearch)) { _ in
            searchIsFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            withAnimation(.easeOut(duration: 0.16)) {
                destination = .settings
                selectedAlbum = nil
                selectedArtist = nil
            }
        }
        .onChange(of: destination) { _, _ in
            selectedAlbum = nil
            selectedArtist = nil
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedAlbum = nil
                selectedArtist = nil
            }
        }
        .onChange(of: player.currentTrack?.id) { _, _ in
            if let track = player.currentTrack {
                library.recordPlay(track)
            }
        }
        .onChange(of: library.playlists) { _, playlists in
            if case .playlist(let id) = destination,
               !playlists.contains(where: { $0.id == id }) {
                destination = .section(.home)
            }
        }
        .alert(
            "无法播放",
            isPresented: Binding(
                get: { player.playbackError != nil },
                set: { if !$0 { player.playbackError = nil } }
            )
        ) {
            Button("好") {
                player.playbackError = nil
            }
        } message: {
            Text(player.playbackError ?? "")
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.16)

            if destination == .settings {
                SettingsView()
            } else if let playlist = activePlaylist {
                PlaylistDetailView(playlist: playlist) {
                    destination = .section(.home)
                } onPlay: { track, tracks in
                    play(track, in: tracks)
                }
            } else if let album = selectedAlbum {
                AlbumDetailView(album: album) {
                    selectedAlbum = nil
                } onPlay: { track, tracks in
                    play(track, in: tracks)
                }
            } else if let artist = selectedArtist {
                ArtistDetailView(artist: artist) {
                    selectedArtist = nil
                } onPlay: { track, tracks in
                    play(track, in: tracks)
                }
            } else if section == .home, normalizedSearch.isEmpty {
                HomeView(
                    tracks: library.tracks,
                    albums: homeAlbums,
                    recentTracks: library.recentlyPlayedTracks(limit: 20),
                    favoriteTracks: library.tracks.filter { library.favoriteIDs.contains($0.id) },
                    openAlbum: { album in
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedAlbum = album
                        }
                    },
                    openNowPlaying: {
                        withAnimation(.spring(response: 0.56, dampingFraction: 0.86)) {
                            showNowPlaying = true
                        }
                    }
                )
            } else if filteredTracks.isEmpty {
                EmptyLibraryView(
                    isSearching: !normalizedSearch.isEmpty,
                    isDropTargeted: isDropTargeted
                )
            } else {
                sectionContent
            }
        }
        .background(Color.hpNavy.opacity(0.32))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .home, .all, .recent, .history, .favorites:
            TrackListView(tracks: filteredTracks) { track in
                play(track, in: filteredTracks)
            }
        case .albums:
            AlbumGridView(albums: albumGroups) { album in
                withAnimation(.easeOut(duration: 0.18)) {
                    selectedAlbum = album
                }
            } onPlay: { album in
                guard let first = album.tracks.first else { return }
                play(first, in: album.tracks)
            }
        case .folders:
            FolderBrowserView(tracks: filteredTracks) { track in
                play(track, in: filteredTracks)
            }
        case .artists:
            ArtistGridView(
                artists: artistGroups,
                onOpen: { artist in
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedArtist = artist
                    }
                },
                onPlay: { artist in
                    guard let first = artist.tracks.first else { return }
                    play(first, in: artist.tracks)
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if selectedAlbum != nil || selectedArtist != nil || activePlaylist != nil {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedAlbum = nil
                        selectedArtist = nil
                        if activePlaylist != nil {
                            destination = .section(.home)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.72))
                        .background(Color.hpTextPrimary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.40))
            }

            Spacer(minLength: 18)

            if showsSortMenu {
                Menu {
                    Picker("排序方式", selection: $sortOrder) {
                        ForEach(TrackSortOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage)
                                .tag(order)
                        }
                    }

                    Divider()

                    Button {
                        sortAscending.toggle()
                    } label: {
                        Label(
                            sortAscending ? "改为降序" : "改为升序",
                            systemImage: sortAscending ? "arrow.down" : "arrow.up"
                        )
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.62))
                        .background(Color.hpTextPrimary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 34)
                .help("排序")
            }

            if destination != .settings {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.40))

                TextField("搜索歌曲、艺人和专辑", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hpTextPrimary)
                    .focused($searchIsFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.32))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(width: 236, height: 34)
            .background(Color.hpTextPrimary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(searchIsFocused ? Color.hpAccent.opacity(0.62) : Color.hpTextPrimary.opacity(0.07), lineWidth: 1)
            }
            }

            IconButton(
                systemName: theme.appearance == .dark ? "sun.max.fill" : "moon.stars.fill",
                help: theme.appearance == .dark ? "切换到白天模式" : "切换到夜间模式",
                size: 13
            ) {
                withAnimation(.easeInOut(duration: 0.28)) {
                    theme.toggleDayNight()
                }
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .background(Color.hpNavy.opacity(0.28))
    }

    private var dropOverlay: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.hpAccent)
                Text("松开以导入音乐")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text("会自动扫描文件夹内的音频")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .background(Color.hpSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.hpAccent.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
        }
        .allowsHitTesting(false)
    }

    private func play(_ track: Track, in tracks: [Track]) {
        if player.currentTrack?.id == track.id {
            player.togglePlayback()
        } else {
            player.play(track, in: tracks)
        }
    }

    private func updateWindowBackground() {
        let windows = NSApp.windows.filter(\.isVisible)
        guard !windows.isEmpty else { return }

        for window in windows {
            if showNowPlaying {
                window.isOpaque = false
                window.backgroundColor = .clear
            } else {
                window.isOpaque = true
                window.backgroundColor = .windowBackgroundColor
            }
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var section: LibrarySection {
        if case .section(let section) = destination {
            return section
        }
        return .home
    }

    private var activePlaylist: Playlist? {
        guard case .playlist(let id) = destination else { return nil }
        return library.playlists.first(where: { $0.id == id })
    }

    private var filteredTracks: [Track] {
        let source: [Track]

        if let playlist = activePlaylist {
            source = library.tracks(in: playlist)
        } else {
            switch section {
            case .home, .all, .albums, .artists, .folders:
                source = library.tracks
            case .recent:
                source = library.tracks.sorted { $0.dateAdded > $1.dateAdded }
            case .history:
                source = library.recentlyPlayedTracks(limit: 200)
            case .favorites:
                source = library.tracks.filter { library.favoriteIDs.contains($0.id) }
            }
        }

        let searched: [Track]
        if normalizedSearch.isEmpty {
            searched = source
        } else {
            searched = source.filter { track in
                track.displayTitle.localizedStandardContains(normalizedSearch)
                    || track.displayArtist.localizedStandardContains(normalizedSearch)
                    || track.displayAlbum.localizedStandardContains(normalizedSearch)
            }
        }

        if activePlaylist != nil, normalizedSearch.isEmpty {
            return searched
        }
        return sorted(searched, by: sortOrder, ascending: sortAscending)
    }

    private var albumGroups: [AlbumGroup] {
        let grouped = Dictionary(grouping: filteredTracks) {
            "\($0.displayAlbum)\u{1f}\($0.displayArtist)"
        }

        return grouped.values.map { tracks in
            AlbumGroup(
                title: tracks[0].displayAlbum,
                artist: tracks[0].displayArtist,
                tracks: tracks.sorted {
                    $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                }
            )
        }
        .sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var homeAlbums: [AlbumGroup] {
        let grouped = Dictionary(grouping: library.tracks) {
            "\($0.displayAlbum)\u{1f}\($0.displayArtist)"
        }

        return grouped.values.map { tracks in
            AlbumGroup(
                title: tracks[0].displayAlbum,
                artist: tracks[0].displayArtist,
                tracks: tracks.sorted { $0.dateAdded > $1.dateAdded }
            )
        }
        .sorted {
            ($0.tracks.first?.dateAdded ?? .distantPast) > ($1.tracks.first?.dateAdded ?? .distantPast)
        }
    }

    private var folderGroups: [FolderGroup] {
        let grouped = Dictionary(grouping: filteredTracks) {
            $0.url.deletingLastPathComponent().standardizedFileURL.path
        }

        return grouped.compactMap { path, tracks in
            guard let name = tracks.first?.url.deletingLastPathComponent().lastPathComponent else {
                return nil
            }
            return FolderGroup(
                path: path,
                name: name,
                tracks: tracks.sorted {
                    $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                }
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var artistGroups: [ArtistGroup] {
        Dictionary(grouping: filteredTracks, by: \.displayArtist)
            .map { name, tracks in
                ArtistGroup(
                    name: name,
                    tracks: tracks.sorted {
                        $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var headerTitle: String {
        if destination == .settings {
            return "设置"
        }
        if let playlist = activePlaylist {
            return playlist.name
        }
        if let album = selectedAlbum {
            return album.title
        }
        if let artist = selectedArtist {
            return artist.name
        }
        return section.title
    }

    private var headerSubtitle: String {
        if destination == .settings {
            return "外观、图标、播放与资料库"
        }
        if !normalizedSearch.isEmpty {
            return "找到 \(filteredTracks.count) 首歌曲"
        }
        if let playlist = activePlaylist {
            return "\(playlist.trackIDs.count) 首歌曲"
        }

        switch section {
        case .home:
            return "为你整理的本地音乐首页"
        case .all:
            return "共 \(library.tracks.count) 首歌曲"
        case .albums:
            return "\(albumGroups.count) 张专辑"
        case .artists:
            return "\(artistGroups.count) 位艺术家"
        case .folders:
            return "\(folderGroups.count) 个文件夹"
        case .recent:
            return "最近加入资料库的音乐"
        case .history:
            return "\(library.history.count) 条播放记录"
        case .favorites:
            return "\(library.favoriteIDs.count) 首收藏"
        }
    }

    private var showsSortMenu: Bool {
        guard destination != .settings else { return false }
        guard selectedAlbum == nil, selectedArtist == nil else { return false }
        if activePlaylist != nil { return true }
        return section != .home && section != .albums && section != .artists && section != .folders
    }

    private func sorted(
        _ tracks: [Track],
        by order: TrackSortOrder,
        ascending: Bool
    ) -> [Track] {
        tracks.sorted { lhs, rhs in
            let result: ComparisonResult
            switch order {
            case .title:
                result = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            case .artist:
                result = lhs.displayArtist.localizedStandardCompare(rhs.displayArtist)
            case .album:
                result = lhs.displayAlbum.localizedStandardCompare(rhs.displayAlbum)
            case .duration:
                result = lhs.duration == rhs.duration
                    ? .orderedSame
                    : (lhs.duration < rhs.duration ? .orderedAscending : .orderedDescending)
            case .dateAdded:
                result = lhs.dateAdded == rhs.dateAdded
                    ? .orderedSame
                    : (lhs.dateAdded < rhs.dateAdded ? .orderedAscending : .orderedDescending)
            }

            if result == .orderedSame {
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}

private struct NoticeView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.hpAccent)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.hpSurface.opacity(0.94), in: Capsule())
        .overlay {
            Capsule().stroke(Color.hpTextPrimary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
    }
}
