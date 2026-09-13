import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var favoriteIDs: Set<UUID> = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var history: [PlayHistoryEntry] = []
    @Published private(set) var isImporting = false
    @Published var importNotice: String?

    private let fileManager = FileManager.default
    private let libraryURL: URL
    private var cancellables = Set<AnyCancellable>()

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directory = appSupport.appendingPathComponent("HarmonyPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        libraryURL = directory.appendingPathComponent("library.json")
        load()
        refreshMetadata()
    }

    func rescanLibrary() {
        let snapshot = tracks
        guard !snapshot.isEmpty, !isImporting else { return }
        isImporting = true
        importNotice = nil

        Task {
            let refreshed = await Task.detached(priority: .utility) {
                await Self.refreshTracks(snapshot)
            }.value

            if refreshed.count == snapshot.count {
                tracks = refreshed.sorted { $0.dateAdded > $1.dateAdded }
                save()
            }
            isImporting = false
            importNotice = "资料库扫描完成。"
            clearNoticeAfterDelay()
        }
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入音乐"
        panel.message = "选择歌曲或包含音乐的文件夹"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = AudioMetadataLoader.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                self?.add(urls: urls)
            }
        }
    }

    func add(urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        importNotice = nil

        Task {
            let expandedURLs = await Task.detached(priority: .userInitiated) {
                Self.expandAndFilter(urls)
            }.value

            let knownPaths = Set(tracks.map { $0.url.standardizedFileURL.path })
            let newURLs = expandedURLs.filter { !knownPaths.contains($0.standardizedFileURL.path) }

            guard !newURLs.isEmpty else {
                isImporting = false
                importNotice = "没有发现新的可播放音频文件。"
                return
            }

            let imported = await Task.detached(priority: .utility) {
                await Self.readTracks(from: newURLs)
            }.value

            tracks.append(contentsOf: imported)
            tracks.sort { $0.dateAdded > $1.dateAdded }
            persistencePayloadChanged()
            isImporting = false
            importNotice = "已导入 \(imported.count) 首歌曲。"
            clearNoticeAfterDelay()
        }
    }

    func remove(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        favoriteIDs.remove(track.id)
        history.removeAll { $0.trackID == track.id }
        playlists = playlists.map { playlist in
            var updated = playlist
            updated.trackIDs.removeAll { $0 == track.id }
            return updated
        }
        persistencePayloadChanged()
    }

    func clearLibrary() {
        tracks.removeAll()
        favoriteIDs.removeAll()
        playlists.removeAll()
        history.removeAll()
        persistencePayloadChanged()
    }

    func toggleFavorite(_ track: Track) {
        if favoriteIDs.contains(track.id) {
            favoriteIDs.remove(track.id)
        } else {
            favoriteIDs.insert(track.id)
        }
        persistencePayloadChanged()
    }

    func isFavorite(_ track: Track) -> Bool {
        favoriteIDs.contains(track.id)
    }

    @discardableResult
    func createPlaylist(named rawName: String) -> Playlist {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(name: name.isEmpty ? "新建歌单" : name)
        playlists.append(playlist)
        persistencePayloadChanged()
        return playlist
    }

    func renamePlaylist(_ playlist: Playlist, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = name
        persistencePayloadChanged()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        persistencePayloadChanged()
    }

    func add(_ track: Track, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].trackIDs.contains(track.id) else { return }
        playlists[index].trackIDs.append(track.id)
        persistencePayloadChanged()
    }

    func remove(_ track: Track, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs.removeAll { $0 == track.id }
        persistencePayloadChanged()
        if playlists[index].trackIDs.isEmpty {
            // Keep empty playlists; they remain valid user-created collections.
        }
    }

    func tracks(in playlist: Playlist) -> [Track] {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { tracksByID[$0] }
    }

    func isTrack(_ track: Track, in playlist: Playlist) -> Bool {
        playlist.trackIDs.contains(track.id)
    }

    func recordPlay(_ track: Track) {
        if let index = history.firstIndex(where: { $0.trackID == track.id }) {
            history[index].lastPlayedAt = .now
            history[index].playCount += 1
        } else {
            history.append(
                PlayHistoryEntry(trackID: track.id, lastPlayedAt: .now, playCount: 1)
            )
        }
        history.sort { $0.lastPlayedAt > $1.lastPlayedAt }
        if history.count > 300 {
            history.removeLast(history.count - 300)
        }
        persistencePayloadChanged()
    }

    func recentlyPlayedTracks(limit: Int = 20) -> [Track] {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return history
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(limit)
            .compactMap { tracksByID[$0.trackID] }
    }

    func playCount(for track: Track) -> Int {
        history.first(where: { $0.trackID == track.id })?.playCount ?? 0
    }

    func reveal(_ track: Track) {
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }

    private func persistencePayloadChanged() {
        save()
    }

    private func refreshMetadata() {
        let snapshot = tracks
        guard !snapshot.isEmpty else { return }

        Task {
            let refreshed = await Task.detached(priority: .utility) {
                await Self.refreshTracks(snapshot)
            }.value

            guard refreshed.count == self.tracks.count else { return }
            if refreshed != self.tracks {
                self.tracks = refreshed.sorted { $0.dateAdded > $1.dateAdded }
                self.save()
            }
        }
    }

    private func clearNoticeAfterDelay() {
        let notice = importNotice
        Task {
            try? await Task.sleep(for: .seconds(4))
            if importNotice == notice {
                importNotice = nil
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        guard let payload = try? JSONDecoder().decode(PersistedLibrary.self, from: data) else { return }
        tracks = payload.tracks.sorted { $0.dateAdded > $1.dateAdded }
        favoriteIDs = Set(payload.favoriteIDs)
        playlists = payload.playlists
        history = payload.history.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    private func save() {
        let payload = PersistedLibrary(
            tracks: tracks,
            favoriteIDs: Array(favoriteIDs),
            playlists: playlists,
            history: history
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    nonisolated private static func expandAndFilter(_ urls: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []
        var visitedPaths = Set<String>()

        for sourceURL in urls {
            let url = sourceURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey]
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let child as URL in enumerator {
                    let values = try? child.resourceValues(forKeys: Set(keys))
                    guard values?.isRegularFile == true else { continue }
                    guard AudioMetadataLoader.supportedExtensions.contains(child.pathExtension.lowercased()) else { continue }
                    let path = child.standardizedFileURL.path
                    if visitedPaths.insert(path).inserted {
                        result.append(child.standardizedFileURL)
                    }
                }
            } else if AudioMetadataLoader.supportedExtensions.contains(url.pathExtension.lowercased()) {
                let path = url.path
                if visitedPaths.insert(path).inserted {
                    result.append(url)
                }
            }
        }
        return result
    }

    nonisolated private static func refreshTracks(_ tracks: [Track]) async -> [Track] {
        var results: [(Int, Track)] = []
        results.reserveCapacity(tracks.count)

        await withTaskGroup(of: (Int, Track).self) { group in
            var nextIndex = 0
            let concurrency = min(8, tracks.count)

            for _ in 0..<concurrency {
                let index = nextIndex
                let track = tracks[index]
                group.addTask(priority: .utility) {
                    let refreshed = await AudioMetadataLoader.makeTrack(
                        from: track.url,
                        id: track.id,
                        dateAdded: track.dateAdded
                    )
                    return (index, refreshed)
                }
                nextIndex += 1
            }

            while let result = await group.next() {
                results.append(result)

                if nextIndex < tracks.count {
                    let index = nextIndex
                    let track = tracks[index]
                    group.addTask(priority: .utility) {
                        let refreshed = await AudioMetadataLoader.makeTrack(
                            from: track.url,
                            id: track.id,
                            dateAdded: track.dateAdded
                        )
                        return (index, refreshed)
                    }
                    nextIndex += 1
                }
            }
        }

        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }

    nonisolated private static func readTracks(from urls: [URL]) async -> [Track] {
        var indexedTracks: [(Int, Track)] = []
        indexedTracks.reserveCapacity(urls.count)

        await withTaskGroup(of: (Int, Track).self) { group in
            var nextIndex = 0
            let concurrency = min(6, urls.count)

            for _ in 0..<concurrency {
                let index = nextIndex
                let url = urls[index]
                group.addTask(priority: .utility) {
                    (index, await AudioMetadataLoader.makeTrack(from: url))
                }
                nextIndex += 1
            }

            while let result = await group.next() {
                indexedTracks.append(result)

                if nextIndex < urls.count {
                    let index = nextIndex
                    let url = urls[index]
                    group.addTask(priority: .utility) {
                        (index, await AudioMetadataLoader.makeTrack(from: url))
                    }
                    nextIndex += 1
                }
            }
        }

        return indexedTracks.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

private struct PersistedLibrary: Codable {
    let tracks: [Track]
    let favoriteIDs: [UUID]
    let playlists: [Playlist]
    let history: [PlayHistoryEntry]

    init(
        tracks: [Track],
        favoriteIDs: [UUID],
        playlists: [Playlist],
        history: [PlayHistoryEntry]
    ) {
        self.tracks = tracks
        self.favoriteIDs = favoriteIDs
        self.playlists = playlists
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        favoriteIDs = try container.decodeIfPresent([UUID].self, forKey: .favoriteIDs) ?? []
        playlists = try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        history = try container.decodeIfPresent([PlayHistoryEntry].self, forKey: .history) ?? []
    }
}
