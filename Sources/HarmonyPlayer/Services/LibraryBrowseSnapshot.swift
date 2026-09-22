import Foundation

/// Cheap, value-only invalidation key. Playback ticks and window resizing are not inputs.
struct LibraryBrowseRequest: Equatable, Sendable {
    let revision: Int
    let isLoading: Bool
    let section: LibrarySection
    let search: String
    let sortOrder: TrackSortOrder
    let ascending: Bool
}

/// An immutable result prepared off the main actor, then published in one transaction.
/// SwiftUI bodies only read these arrays; no sorting/grouping is performed during rendering.
struct LibraryBrowseSnapshot: Sendable {
    var request: LibraryBrowseRequest?
    var tracks: [Track] = []
    var albums: [AlbumGroup] = []
    var artists: [ArtistGroup] = []
    var folders: [FolderGroup] = []
    var homeAlbums: [AlbumGroup] = []
    var favorites: [Track] = []
    var recentTracks: [Track] = []

    static func build(
        request: LibraryBrowseRequest,
        tracks: [Track],
        favoriteIDs: Set<UUID>,
        recentTracks: [Track]
    ) -> Self {
        var result = Self(request: request)
        guard !Task.isCancelled else { return result }

        if request.section == .home, request.search.isEmpty {
            result.tracks = tracks
            result.favorites = tracks.filter { favoriteIDs.contains($0.id) }
            result.recentTracks = Array(recentTracks.prefix(20))
            // The store already keeps tracks newest-first. Preserve that ordering inside albums.
            let grouped = Dictionary(grouping: tracks) { AlbumKey(title: $0.displayAlbum, artist: $0.displayArtist) }
            result.homeAlbums = grouped.map { key, songs in
                AlbumGroup(title: key.title, artist: key.artist, tracks: songs)
            }.sorted {
                ($0.tracks.first?.dateAdded ?? .distantPast) > ($1.tracks.first?.dateAdded ?? .distantPast)
            }
            return result
        }

        let source: [Track]
        switch request.section {
        case .favorites: source = tracks.filter { favoriteIDs.contains($0.id) }
        case .history: source = recentTracks
        default: source = tracks
        }
        let query = request.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredQuery = query.lowercased()
        // Normalize display fields once per song, not on every comparison in O(n log n) sorting.
        var rows: [SearchRow] = []
        rows.reserveCapacity(source.count)
        for track in source {
            guard !Task.isCancelled else { return result }
            let row = SearchRow(track: track)
            if query.isEmpty || row.matches(query: query, loweredQuery: loweredQuery) {
                rows.append(row)
            }
        }
        let order: TrackSortOrder = [.albums, .artists, .folders].contains(request.section) ? .title : request.sortOrder
        let ascending = [.albums, .artists, .folders].contains(request.section) ? true : request.ascending
        rows.sort { compare($0, $1, order: order, ascending: ascending) }
        guard !Task.isCancelled else { return result }
        result.tracks = rows.map(\.track)

        switch request.section {
        case .albums:
            result.albums = Dictionary(grouping: rows) { AlbumKey(title: $0.album, artist: $0.artist) }
                .map { key, songs in AlbumGroup(title: key.title, artist: key.artist, tracks: songs.map(\.track)) }
                .sorted {
                    let comparison = $0.title.localizedStandardCompare($1.title)
                    return comparison == .orderedSame
                        ? $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
                        : comparison == .orderedAscending
                }
        case .artists:
            result.artists = Dictionary(grouping: rows, by: \.artist)
                .map { ArtistGroup(name: $0.key, tracks: $0.value.map(\.track)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .folders:
            result.folders = Dictionary(grouping: result.tracks) {
                $0.url.deletingLastPathComponent().standardizedFileURL.path
            }.map { path, songs in
                FolderGroup(path: path, name: URL(fileURLWithPath: path).lastPathComponent, tracks: songs)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        default: break
        }
        return result
    }

    private struct AlbumKey: Hashable { let title: String; let artist: String }
    private struct SearchRow {
        let track: Track
        let title: String
        let artist: String
        let album: String
        init(track: Track) {
            self.track = track
            title = track.displayTitle
            artist = track.displayArtist
            album = track.displayAlbum
        }

        /// 原文包含、全拼包含、首字母包含，三者任一命中即匹配。
        /// 拼音键由 PinyinIndex 按原文缓存，重复按键零转换开销。
        func matches(query: String, loweredQuery: String) -> Bool {
            if title.localizedStandardContains(query)
                || artist.localizedStandardContains(query)
                || album.localizedStandardContains(query) {
                return true
            }
            return PinyinIndex.keys(for: title).matches(loweredQuery)
                || PinyinIndex.keys(for: artist).matches(loweredQuery)
                || PinyinIndex.keys(for: album).matches(loweredQuery)
        }
    }

    private static func compare(_ lhs: SearchRow, _ rhs: SearchRow, order: TrackSortOrder, ascending: Bool) -> Bool {
        let comparison: ComparisonResult
        switch order {
        case .title: comparison = lhs.title.localizedStandardCompare(rhs.title)
        case .artist: comparison = lhs.artist.localizedStandardCompare(rhs.artist)
        case .album: comparison = lhs.album.localizedStandardCompare(rhs.album)
        case .duration:
            comparison = lhs.track.duration == rhs.track.duration ? .orderedSame
                : (lhs.track.duration < rhs.track.duration ? .orderedAscending : .orderedDescending)
        case .dateAdded:
            comparison = lhs.track.dateAdded == rhs.track.dateAdded ? .orderedSame
                : (lhs.track.dateAdded < rhs.track.dateAdded ? .orderedAscending : .orderedDescending)
        }
        if comparison == .orderedSame {
            let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
            // Stable identities/order even for same-titled tracks from different files.
            return titleComparison == .orderedSame
                ? lhs.track.id.uuidString < rhs.track.id.uuidString
                : titleComparison == .orderedAscending
        }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}
