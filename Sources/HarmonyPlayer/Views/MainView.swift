import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var destination: LibraryDestination = .section(.home)
    @State private var selectedAlbum: AlbumGroup?
    @State private var selectedArtist: ArtistGroup?
    @State private var searchText = ""
    @State private var showQueue = false
    @State private var showNowPlaying = false
    @State private var isDropTargeted = false
    @State private var headerSort: TrackSortOrder?
    @State private var headerAscending = true
    @State private var browse = LibraryBrowseSnapshot(request: nil)
    @Namespace private var nowPlayingTransition
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            if showNowPlaying {
                NowPlayingView(transitionNamespace: nowPlayingTransition)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .frame(width: geometry.size.width, height: geometry.size.height)
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
            if !library.isLoading {
                player.restorePlaybackState(from: library.tracks)
                ArtworkPreloader.shared.preloadIfNeeded(tracks: library.tracks)
            }
            updateWindowBackground()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                searchIsFocused = false
            }
        }
        .onChange(of: library.isLoading) { _, loading in
            guard !loading else { return }
            ArtworkPreloader.shared.preloadIfNeeded(tracks: library.tracks)
        }
        .task(id: browseRequest) {
            await refreshBrowseSnapshot()
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

    /// Detail panes fade in place; slides are reserved for side panels like the queue.
    private var detailTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
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
                .transition(detailTransition)
            } else if let album = selectedAlbum {
                AlbumDetailView(album: album) {
                    selectedAlbum = nil
                } onPlay: { track, tracks in
                    play(track, in: tracks)
                }
                .transition(detailTransition)
            } else if let artist = selectedArtist {
                ArtistDetailView(artist: artist) {
                    selectedArtist = nil
                } onPlay: { track, tracks in
                    play(track, in: tracks)
                }
                .transition(detailTransition)
            } else if let loadError = library.loadErrorMessage {
                // A failed load leaves the library empty; showing the empty-state
                // home here would read as "you have no music" instead of an error.
                LibraryLoadErrorView(message: loadError)
            } else if section == .home, normalizedSearch.isEmpty {
                HomeView(
                    tracks: library.tracks,
                    favoriteTracks: library.tracks.filter { library.favoriteIDs.contains($0.id) },
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
                    .disabled(browse.request != browseRequest)
            }
        }
        .background(Color.hpNavy.opacity(0.32))
        .overlay(alignment: .topTrailing) {
            if browse.request != browseRequest && !library.isLoading && destination != .settings {
                ProgressView().controlSize(.mini).padding(.top, 26).padding(.trailing, 12)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = library.loadErrorMessage ?? library.saveErrorMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(Color.hpTextPrimary)
                    .padding(10).frame(maxWidth: .infinity)
                    .background(Color.hpGold.opacity(0.18))
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .home, .all, .recent, .history, .favorites:
            TrackListView(
                tracks: sectionDisplayTracks,
                sortColumn: headerSort,
                sortAscending: headerAscending,
                onSortTap: toggleHeaderSort
            ) { track in
                play(track, in: sectionDisplayTracks)
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
            FolderBrowserView(groups: folderGroups) { track in
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
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: headerTitle)
                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.40))
            }

            Spacer(minLength: 18)

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

    private var filteredTracks: [Track] { browse.tracks }
    private var albumGroups: [AlbumGroup] { browse.albums }
    private var folderGroups: [FolderGroup] { browse.folders }
    private var artistGroups: [ArtistGroup] { browse.artists }

    private var browseRequest: LibraryBrowseRequest {
        LibraryBrowseRequest(revision: library.revision, isLoading: library.isLoading,
                             section: section, search: normalizedSearch,
                             sortOrder: .dateAdded, ascending: false)
    }

    /// 列头排序后的展示顺序（同时用于点击行时的播放队列，保证顺序一致）。
    private var sectionDisplayTracks: [Track] {
        guard let column = headerSort else { return filteredTracks }
        return filteredTracks.sorted { lhs, rhs in
            let ascending: Bool
            switch column {
            case .title:
                ascending = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            case .album:
                ascending = lhs.displayAlbum.localizedStandardCompare(rhs.displayAlbum) == .orderedAscending
            case .duration:
                ascending = lhs.duration < rhs.duration
            default:
                ascending = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
            return headerAscending ? ascending : !ascending
        }
    }

    /// 点击列头：首次点击升序，再点同列切换降序，点其他列回到升序。
    private func toggleHeaderSort(_ column: TrackSortOrder) {
        if headerSort == column {
            headerAscending.toggle()
        } else {
            headerSort = column
            headerAscending = true
        }
    }

    private func refreshBrowseSnapshot() async {
        guard !library.isLoading else { return }
        let request = browseRequest
        // Coalesce keystrokes without delaying navigation or clearing the search field.
        if !request.search.isEmpty {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        let tracks = library.tracks
        let favorites = library.favoriteIDs
        let recent = library.recentlyPlayedTracks(limit: 200)
        let work = Task.detached(priority: .userInitiated) {
            LibraryBrowseSnapshot.build(request: request, tracks: tracks,
                                        favoriteIDs: favorites, recentTracks: recent)
        }
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled, request == browseRequest else { return }
        // Never animate a many-thousand-row insertion/reorder.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { browse = result }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(library.isLoading ? "正在载入资料库…" : "正在整理音乐…")
                .font(.system(size: 12))
                .foregroundStyle(Color.hpTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

}

private struct LibraryLoadErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.hpGold.opacity(0.14))
                    .frame(width: 100, height: 100)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.hpGold)
            }

            VStack(spacing: 7) {
                Text("资料库无法载入")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                Text("为避免覆盖原文件，修改已暂停。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.34))
            }

            Button {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Label("前往设置", systemImage: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
            }
            .buttonStyle(AccentFillButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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
        .background(Color.hpSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.hpTextPrimary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
    }
}
