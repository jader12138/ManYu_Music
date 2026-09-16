import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = [] {
        didSet {
            tracksGeneration &+= 1
            if let prepared = preparedDerivedCache {
                derivedCache = prepared
                preparedDerivedCache = nil
            } else {
                derivedCache = TrackDerivedCache.make(from: tracks)
            }
        }
    }
    @Published private(set) var favoriteIDs: Set<UUID> = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var history: [PlayHistoryEntry] = []
    @Published private(set) var isImporting = false
    @Published var importNotice: String?

    /// `true` until the cached library has been read from disk off the main thread.
    @Published private(set) var isLoading = true

    /// Bumped only when persisted library content really changes. Views can use it as a
    /// `.task(id:)` trigger for background queries; transient state such as
    /// `isImporting` or `importNotice` never bumps it.
    @Published private(set) var revision: Int = 0

    /// Non-nil when the cached library file exists but could not be decoded.
    @Published private(set) var loadErrorMessage: String?

    /// Non-nil when the most recent disk write failed.
    @Published private(set) var saveErrorMessage: String?

    /// `true` after a load failure: writing is disabled so the unreadable original
    /// file is never silently overwritten.
    @Published private(set) var isPersistenceSuppressed = false

    /// `true` while the library may be mutated. A load failure suppresses persistence
    /// completely, so mutations are blocked too: an in-memory-only import that can never
    /// be saved would be silently lost. Views can use this to disable editing controls.
    var canEdit: Bool { !isLoading && !isPersistenceSuppressed }

    /// Cached track index and aggregate counts, rebuilt only when `tracks` changes.
    private var derivedCache = TrackDerivedCache.empty

    /// A cache built off the main thread, consumed by the next `tracks` assignment so
    /// loading and importing never trim/standardize the whole library on the main thread.
    private var preparedDerivedCache: TrackDerivedCache?

    /// Increments whenever `tracks` is replaced. Used to detect a concurrent edit that
    /// landed while a prepared cache was being built off the main thread.
    private var tracksGeneration = 0

    private let libraryURL: URL
    private var cancellables = Set<AnyCancellable>()

    /// Serial queue that owns every disk write, so writes stay ordered.
    private let saveQueue = DispatchQueue(
        label: "HarmonyPlayer.LibraryStore.persistence",
        qos: .utility
    )
    private var pendingSaveWorkItem: DispatchWorkItem?
    private var pendingPayload: PersistedLibrary?
    private var saveToken = 0

    /// Paths removed while an import is in flight. Stale import results are filtered
    /// against this set so a concurrent delete cannot resurrect a removed song.
    private var removedDuringImport: Set<String> = []

    /// Increments on every `clearLibrary()`, even when the library is already empty.
    /// In-flight imports/rescans compare against it so a clear discards everything that
    /// was requested before it, not just the paths that happened to be known then.
    private var clearGeneration = 0

    private static let loadingNotice = "资料库正在载入，请稍候再试。"
    private static let suppressedNotice = "资料库文件损坏，已暂停修改以保护原文件。"
    private static let saveDebounceInterval = DispatchTimeInterval.milliseconds(400)

    init(libraryURL: URL? = nil) {
        if let libraryURL {
            self.libraryURL = libraryURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory

            self.libraryURL = appSupport
                .appendingPathComponent("HarmonyPlayer", isDirectory: true)
                .appendingPathComponent("library.json")
        }

        // `willTerminate` is delivered synchronously on the main thread, so the pending
        // snapshot can be flushed before the process exits. A `Task` would be too late.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.flushPendingSave()
                }
            }
            .store(in: &cancellables)

        startLoading()
    }

    func rescanLibrary() {
        guard canEdit else {
            presentUnavailableNotice()
            return
        }

        let snapshot = tracks
        guard !snapshot.isEmpty, !isImporting else { return }
        isImporting = true
        importNotice = nil
        removedDuringImport.removeAll()

        let snapshotIDs = Set(snapshot.map(\.id))
        let snapshotGeneration = tracksGeneration
        let clear = clearGeneration

        Task {
            let refreshed = await Task.detached(priority: .utility) {
                await Self.refreshTracks(snapshot)
            }.value

            defer {
                isImporting = false
                removedDuringImport.removeAll()
                clearNoticeAfterDelay()
            }

            guard clearGeneration == clear else { return }

            // Merge by ID, and only while the library still holds exactly the scanned
            // collection. A count comparison would let a concurrent edit apply stale
            // results.
            guard Set(tracks.map(\.id)) == snapshotIDs, tracksGeneration == snapshotGeneration else {
                importNotice = "资料库已变更，本次扫描结果已丢弃。"
                return
            }

            let refreshedByID = Dictionary(
                refreshed.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            let merged = tracks
                .map { refreshedByID[$0.id] ?? $0 }
                .sorted { $0.dateAdded > $1.dateAdded }

            guard merged != tracks else {
                importNotice = "资料库扫描完成。"
                return
            }

            let cache = await Task.detached(priority: .utility) {
                TrackDerivedCache.make(from: merged)
            }.value

            guard clearGeneration == clear, tracksGeneration == snapshotGeneration else {
                importNotice = "资料库已变更，本次扫描结果已丢弃。"
                return
            }

            preparedDerivedCache = cache
            tracks = merged
            libraryContentDidChange()
            importNotice = "资料库扫描完成。"
        }
    }

    func presentImportPanel() {
        guard canEdit else {
            presentUnavailableNotice()
            return
        }

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
        guard !urls.isEmpty else { return }
        guard canEdit else {
            presentUnavailableNotice()
            return
        }
        guard !isImporting else { return }
        isImporting = true
        importNotice = nil
        removedDuringImport.removeAll()

        let clear = clearGeneration

        Task {
            defer {
                isImporting = false
                removedDuringImport.removeAll()
                clearNoticeAfterDelay()
            }

            let expandedURLs = await Task.detached(priority: .userInitiated) {
                Self.expandAndFilter(urls)
            }.value

            // A clear requested while this import was in flight discards all of it.
            guard clearGeneration == clear else { return }

            let knownPaths = Set(tracks.map { $0.url.standardizedFileURL.path })
            let removed = removedDuringImport
            let newURLs = expandedURLs.filter { url in
                let path = url.standardizedFileURL.path
                return !knownPaths.contains(path) && !removed.contains(path)
            }

            guard !newURLs.isEmpty else {
                importNotice = "没有发现新的可播放音频文件。"
                return
            }

            let imported = await Task.detached(priority: .utility) {
                await Self.readTracks(from: newURLs)
            }.value

            guard clearGeneration == clear else { return }

            // Re-check against the live library right before committing: nothing that was
            // deleted (or already present) during the import may come back.
            let livePaths = Set(tracks.map { $0.url.standardizedFileURL.path })
            let blockedPaths = removedDuringImport
            let accepted = imported.filter { track in
                let path = track.url.standardizedFileURL.path
                return !livePaths.contains(path) && !blockedPaths.contains(path)
            }

            guard !accepted.isEmpty else {
                importNotice = "没有发现新的可播放音频文件。"
                return
            }

            let baseGeneration = tracksGeneration
            let updated = (tracks + accepted).sorted { $0.dateAdded > $1.dateAdded }

            let cache = await Task.detached(priority: .utility) {
                TrackDerivedCache.make(from: updated)
            }.value

            guard clearGeneration == clear else { return }

            if tracksGeneration == baseGeneration {
                preparedDerivedCache = cache
                tracks = updated
            } else {
                // The library moved while the cache was built: re-merge against the live
                // value so the concurrent edit survives, and let the `didSet` rebuild.
                let currentPaths = Set(tracks.map { $0.url.standardizedFileURL.path })
                var reconciled = tracks
                reconciled.append(contentsOf: accepted.filter {
                    !currentPaths.contains($0.url.standardizedFileURL.path)
                })
                reconciled.sort { $0.dateAdded > $1.dateAdded }
                tracks = reconciled
            }

            libraryContentDidChange()
            importNotice = "已导入 \(accepted.count) 首歌曲。"
        }
    }

    func remove(_ track: Track) {
        guard canEdit else { return }
        guard tracks.contains(where: { $0.id == track.id }) else { return }

        if isImporting {
            removedDuringImport.insert(track.url.standardizedFileURL.path)
        }

        tracks.removeAll { $0.id == track.id }
        favoriteIDs.remove(track.id)
        history.removeAll { $0.trackID == track.id }
        playlists = playlists.map { playlist in
            var updated = playlist
            updated.trackIDs.removeAll { $0 == track.id }
            return updated
        }
        libraryContentDidChange()
    }

    func clearLibrary() {
        guard canEdit else { return }

        // Invalidate every in-flight import/rescan, even when the library is already
        // empty: the user asked for an empty library, so nothing requested before this
        // point may land afterwards.
        clearGeneration &+= 1

        guard !tracks.isEmpty || !favoriteIDs.isEmpty || !playlists.isEmpty || !history.isEmpty else {
            return
        }

        tracks.removeAll()
        favoriteIDs.removeAll()
        playlists.removeAll()
        history.removeAll()
        libraryContentDidChange()
    }

    func toggleFavorite(_ track: Track) {
        guard canEdit else { return }

        if favoriteIDs.contains(track.id) {
            favoriteIDs.remove(track.id)
        } else {
            favoriteIDs.insert(track.id)
        }
        libraryContentDidChange()
    }

    func isFavorite(_ track: Track) -> Bool {
        favoriteIDs.contains(track.id)
    }

    @discardableResult
    func createPlaylist(named rawName: String) -> Playlist {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(name: name.isEmpty ? "新建歌单" : name)
        guard canEdit else { return playlist }
        playlists.append(playlist)
        libraryContentDidChange()
        return playlist
    }

    func renamePlaylist(_ playlist: Playlist, to rawName: String) {
        guard canEdit else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = playlists.firstIndex(where: { $0.id == playlist.id }),
              playlists[index].name != name else { return }
        playlists[index].name = name
        libraryContentDidChange()
    }

    func deletePlaylist(_ playlist: Playlist) {
        guard canEdit else { return }
        guard playlists.contains(where: { $0.id == playlist.id }) else { return }
        playlists.removeAll { $0.id == playlist.id }
        libraryContentDidChange()
    }

    func add(_ track: Track, to playlistID: UUID) {
        guard canEdit else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].trackIDs.contains(track.id) else { return }
        playlists[index].trackIDs.append(track.id)
        libraryContentDidChange()
    }

    func remove(_ track: Track, from playlistID: UUID) {
        guard canEdit else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].trackIDs.contains(track.id) else { return }
        playlists[index].trackIDs.removeAll { $0 == track.id }
        libraryContentDidChange()
        if playlists[index].trackIDs.isEmpty {
            // Keep empty playlists; they remain valid user-created collections.
        }
    }

    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap { derivedCache.tracksByID[$0] }
    }

    func isTrack(_ track: Track, in playlist: Playlist) -> Bool {
        playlist.trackIDs.contains(track.id)
    }

    func recordPlay(_ track: Track) {
        guard canEdit else { return }

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
        libraryContentDidChange()
    }

    func recentlyPlayedTracks(limit: Int = 20) -> [Track] {
        history
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(limit)
            .compactMap { derivedCache.tracksByID[$0.trackID] }
    }

    func playCount(for track: Track) -> Int {
        history.first(where: { $0.trackID == track.id })?.playCount ?? 0
    }

    func reveal(_ track: Track) {
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }

    var albumCount: Int { derivedCache.albumCount }
    var artistCount: Int { derivedCache.artistCount }
    var folderCount: Int { derivedCache.folderCount }

    /// Synchronously writes the newest snapshot, if any, on the serial save queue.
    /// Cancels a debounced write first, so callers always observe the latest state on
    /// disk when this returns. Exposed for tests and for app termination.
    func flushPendingSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil

        guard !isPersistenceSuppressed, let payload = pendingPayload else { return }

        var message: String?
        saveQueue.sync {
            message = Self.write(payload, to: libraryURL)
        }

        if let message {
            // Keep `pendingPayload` so a later flush can retry the write.
            saveErrorMessage = "资料库保存失败：\(message)"
        } else {
            saveErrorMessage = nil
            pendingPayload = nil
        }
    }

    private func startLoading() {
        let url = libraryURL
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.readLibrary(at: url)
            }.value
            self?.apply(outcome)
        }
    }

    private func apply(_ outcome: LoadOutcome) {
        switch outcome {
        case .missing:
            // No cache yet: start from an empty library.
            break
        case .loaded(let payload, let cache):
            preparedDerivedCache = cache
            tracks = payload.tracks
            favoriteIDs = Set(payload.favoriteIDs)
            playlists = payload.playlists
            history = payload.history
            revision &+= 1
        case .failed(let message):
            // Never overwrite the unreadable original file.
            isPersistenceSuppressed = true
            loadErrorMessage = "无法读取资料库文件：\(message)"
            importNotice = Self.suppressedNotice
        }
        isLoading = false
    }

    private func libraryContentDidChange() {
        revision &+= 1
        scheduleSave()
    }

    private func scheduleSave() {
        guard !isPersistenceSuppressed else { return }

        let payload = PersistedLibrary(
            tracks: tracks,
            favoriteIDs: Array(favoriteIDs),
            playlists: playlists,
            history: history
        )
        pendingPayload = payload
        saveToken &+= 1
        let token = saveToken
        let url = libraryURL

        // Coalesce bursts of edits into a single write of the newest snapshot.
        pendingSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let message = Self.write(payload, to: url)
            Task { @MainActor in
                // Check the token before touching any state, so a stale completion can
                // never report over, or clear, a newer snapshot.
                guard let self, self.saveToken == token else { return }

                if let message {
                    // Keep `pendingPayload` so a later flush can retry the write.
                    self.saveErrorMessage = "资料库保存失败：\(message)"
                } else {
                    self.saveErrorMessage = nil
                    self.pendingPayload = nil
                }
            }
        }
        pendingSaveWorkItem = work
        saveQueue.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: work)
    }

    private func presentUnavailableNotice() {
        guard let message = unavailableNotice else { return }
        importNotice = message
        clearNoticeAfterDelay()
    }

    private var unavailableNotice: String? {
        if isLoading { return Self.loadingNotice }
        if isPersistenceSuppressed { return Self.suppressedNotice }
        return nil
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

    nonisolated private static func readLibrary(at url: URL) -> LoadOutcome {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(PersistedLibrary.self, from: data)
            let sortedTracks = payload.tracks.sorted { $0.dateAdded > $1.dateAdded }
            return .loaded(
                PersistedLibrary(
                    tracks: sortedTracks,
                    favoriteIDs: payload.favoriteIDs,
                    playlists: payload.playlists,
                    history: payload.history.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
                ),
                TrackDerivedCache.make(from: sortedTracks)
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Encodes and atomically writes on the calling (serial save) queue. The library
    /// directory is only created here, so merely reading or starting the app never
    /// touches the real library location. Returns a message on failure, `nil` on success.
    nonisolated private static func write(_ payload: PersistedLibrary, to url: URL) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
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

private enum LoadOutcome: Sendable {
    case missing
    case loaded(PersistedLibrary, TrackDerivedCache)
    case failed(String)
}

/// Track index plus aggregate counts, built off the main thread and handed to
/// `LibraryStore` so a `tracks` assignment never has to trim or standardize paths on
/// the main thread.
private struct TrackDerivedCache: Sendable {
    let tracksByID: [UUID: Track]
    let albumCount: Int
    let artistCount: Int
    let folderCount: Int

    static let empty = TrackDerivedCache(
        tracksByID: [:],
        albumCount: 0,
        artistCount: 0,
        folderCount: 0
    )

    static func make(from tracks: [Track]) -> TrackDerivedCache {
        var index: [UUID: Track] = [:]
        index.reserveCapacity(tracks.count)

        var albums = Set<String>()
        var artists = Set<String>()
        var folders = Set<String>()
        albums.reserveCapacity(tracks.count)
        artists.reserveCapacity(tracks.count)
        folders.reserveCapacity(tracks.count)

        for track in tracks {
            index[track.id] = track
            albums.insert("\(track.displayAlbum)\u{1f}\(track.displayArtist)")
            artists.insert(track.displayArtist)
            folders.insert(track.url.deletingLastPathComponent().standardizedFileURL.path)
        }

        return TrackDerivedCache(
            tracksByID: index,
            albumCount: albums.count,
            artistCount: artists.count,
            folderCount: folders.count
        )
    }
}

private struct PersistedLibrary: Codable, Sendable {
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
