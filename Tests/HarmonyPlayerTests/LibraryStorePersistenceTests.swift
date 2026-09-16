import XCTest

@testable import HarmonyPlayer

/// `LibraryStore` 的载入 / 持久化契约。
///
/// 所有用例都用 `LibraryStore(libraryURL:)` 指向自己临时目录里的 library.json，
/// 不会读取或写入用户的 Application Support、音乐目录或 UserDefaults。
/// 每个用例的目录互相独立，teardown 只删除自己创建的那一个路径。
@MainActor
final class LibraryStorePersistenceTests: XCTestCase {

    // MARK: 1. 旧 JSON 兼容 + 派生计数

    func testLoadsLegacyJSONAndReportsCachedCounts() async throws {
        let workspace = makeTempWorkspace()
        let sharedByFirst = makeTestTrack(
            id: testUUID(1), title: "Track A", artist: "甲", album: "精选",
            duration: 100, dateAdded: Date(timeIntervalSince1970: 300),
            directory: "/music/album-a", fileName: "a1.mp3"
        )
        let sharedBySecond = makeTestTrack(
            id: testUUID(2), title: "Track B", artist: "乙", album: "精选",
            duration: 200, dateAdded: Date(timeIntervalSince1970: 200),
            directory: "/music/album-b", fileName: "b1.mp3"
        )
        let otherAlbum = makeTestTrack(
            id: testUUID(3), title: "Track C", artist: "甲", album: "精选",
            duration: 300, dateAdded: Date(timeIntervalSince1970: 100),
            directory: "/music/album-a", fileName: "a2.mp3"
        )

        // 旧格式：没有 playlists / history 字段，另外带一个未来新增的未知字段。
        let legacy = try encodeLegacyLibraryJSON(
            tracks: [sharedByFirst, sharedBySecond, otherAlbum],
            favoriteIDs: [testUUID(3)],
            extraKeys: ["futureField": ["unknown": true]]
        )
        try workspace.write(legacy, to: "library.json")

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)

        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.canEdit)
        XCTAssertNil(store.loadErrorMessage)
        XCTAssertFalse(store.isPersistenceSuppressed)
        XCTAssertEqual(
            store.tracks.map(\.id),
            [testUUID(1), testUUID(2), testUUID(3)],
            "载入后按 dateAdded 降序"
        )
        XCTAssertEqual(store.favoriteIDs, [testUUID(3)])
        XCTAssertTrue(store.playlists.isEmpty, "旧 JSON 缺少 playlists 字段应回退为空数组")
        XCTAssertTrue(store.history.isEmpty, "旧 JSON 缺少 history 字段应回退为空数组")
        XCTAssertEqual(store.albumCount, 2, "同名专辑不同艺人算两张，同专辑同艺人的两首只算一张")
        XCTAssertEqual(store.artistCount, 2)
        XCTAssertEqual(store.folderCount, 2, "同一目录下的两首只算一个文件夹")
    }

    // MARK: 2. 载入期间禁止 mutation

    func testMutationsAreRejectedWhileLoading() async throws {
        let workspace = makeTempWorkspace()
        // init 返回时载入 Task 还没有机会运行，isLoading 一定还是 true。
        let store = LibraryStore(libraryURL: workspace.libraryURL)
        XCTAssertTrue(store.isLoading)
        XCTAssertFalse(store.canEdit)

        let track = makeTestTrack(title: "载入中")
        store.toggleFavorite(track)
        store.remove(track)
        store.clearLibrary()
        let created = store.createPlaylist(named: "载入中歌单")
        store.add(track, to: created.id)
        store.renamePlaylist(created, to: "改名后")
        store.deletePlaylist(created)
        store.recordPlay(track)
        store.add(urls: [workspace.path("missing.mp3")])

        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertTrue(store.tracks.isEmpty)
        XCTAssertTrue(store.playlists.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.revision, 0, "载入期间的调用不产生版本变化")
        XCTAssertFalse(store.isImporting, "载入期间不应真的开始导入")
        XCTAssertEqual(store.importNotice, "资料库正在载入，请稍候再试。")

        await waitForLibraryLoad(store)
        XCTAssertTrue(store.canEdit)
        XCTAssertEqual(store.revision, 0, "载入缺失文件本身不产生 revision")
    }

    // MARK: 3. 损坏 JSON 不覆盖原文件

    func testCorruptJSONSuppressesPersistenceAndLeavesFileIntact() async throws {
        let workspace = makeTempWorkspace()
        let garbage = Data("{ 这不是合法的资料库 JSON".utf8)
        try workspace.write(garbage, to: "library.json")

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)

        XCTAssertTrue(store.isPersistenceSuppressed)
        XCTAssertNotNil(store.loadErrorMessage)
        XCTAssertFalse(store.canEdit)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.importNotice, "资料库文件损坏，已暂停修改以保护原文件。")

        let track = makeTestTrack(title: "不应落盘")
        store.toggleFavorite(track)
        store.createPlaylist(named: "不应落盘歌单")
        store.clearLibrary()
        store.flushPendingSave()

        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertTrue(store.playlists.isEmpty)
        XCTAssertNil(store.saveErrorMessage, "抑制状态下根本不应尝试写入")
        XCTAssertEqual(try workspace.read("library.json"), garbage, "损坏的原文件必须原样保留")
    }

    // MARK: 4. 收藏 / 歌单变更 flush 后重载仍在

    func testFavoriteAndPlaylistChangesSurviveFlushAndReload() async throws {
        let workspace = makeTempWorkspace()
        let first = makeTestTrack(id: testUUID(41), title: "夜曲", artist: "甲")
        let second = makeTestTrack(id: testUUID(42), title: "晴天", artist: "乙")
        try workspace.write(
            try encodeLegacyLibraryJSON(tracks: [first, second], favoriteIDs: []),
            to: "library.json"
        )

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)
        XCTAssertEqual(store.tracks.count, 2)

        store.toggleFavorite(first)
        let playlist = store.createPlaylist(named: "  夜间歌单  ")
        XCTAssertEqual(playlist.name, "夜间歌单", "歌单名应裁剪首尾空白")
        store.add(first, to: playlist.id)
        store.add(second, to: playlist.id)
        store.flushPendingSave()
        XCTAssertNil(store.saveErrorMessage)

        let reloaded = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(reloaded)

        XCTAssertEqual(reloaded.favoriteIDs, [first.id])
        XCTAssertEqual(reloaded.playlists.count, 1)
        let restored = try XCTUnwrap(reloaded.playlists.first)
        XCTAssertEqual(restored.name, "夜间歌单")
        XCTAssertEqual(restored.trackIDs, [first.id, second.id])
        XCTAssertEqual(reloaded.tracks.count, 2)
        XCTAssertEqual(reloaded.tracks(in: restored).map(\.id), [first.id, second.id])
    }

    // MARK: 5. 连续修改只有最新快照落盘

    func testLatestSnapshotWinsAcrossRapidSaves() async throws {
        let workspace = makeTempWorkspace()
        let first = makeTestTrack(id: testUUID(51), title: "First")
        let second = makeTestTrack(id: testUUID(52), title: "Second")
        try workspace.write(
            try encodeLegacyLibraryJSON(tracks: [first, second], favoriteIDs: []),
            to: "library.json"
        )

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)

        // 三次快速修改：每次都会取消上一次尚未落盘的防抖任务。
        store.toggleFavorite(first)
        store.toggleFavorite(second)
        let playlist = store.createPlaylist(named: "最新歌单")
        store.add(first, to: playlist.id)
        store.flushPendingSave()

        let flushed = try decodeLibraryFile(try workspace.read("library.json"))
        XCTAssertEqual(Set(flushed.favoriteIDs), Set([first.id, second.id]))
        XCTAssertEqual(flushed.playlists.map(\.name), ["最新歌单"])
        XCTAssertNil(store.saveErrorMessage)

        // 等被取消的防抖窗口过去：旧快照不能把文件写回中间状态。
        await settleSaveDebounce()
        let settled = try decodeLibraryFile(try workspace.read("library.json"))
        XCTAssertEqual(Set(settled.favoriteIDs), Set([first.id, second.id]))
        XCTAssertEqual(settled.playlists.map(\.name), ["最新歌单"])
        XCTAssertNil(store.saveErrorMessage)
    }

    // MARK: 6. 写失败可见（父路径是文件）

    func testSaveFailureIsVisibleWhenParentPathIsAFile() async throws {
        let workspace = makeTempWorkspace()
        try workspace.write(Data("blocker".utf8), to: "blocker")
        let libraryURL = workspace.path("blocker/library.json")

        let store = LibraryStore(libraryURL: libraryURL)
        await waitForLibraryLoad(store)
        XCTAssertTrue(store.canEdit, "文件不存在属于 missing，不算损坏")

        store.toggleFavorite(makeTestTrack(title: "写失败"))
        store.flushPendingSave()

        let message = try XCTUnwrap(store.saveErrorMessage)
        XCTAssertTrue(message.contains("资料库保存失败"), "实际信息：\(message)")

        // 失败时保留待写快照，重试仍然可见失败，且不会凭空出现文件。
        store.flushPendingSave()
        XCTAssertNotNil(store.saveErrorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path))
    }

    // MARK: 7. 空库 clear 不崩溃 / 不存在路径 init 不建目录

    func testClearOnEmptyLibraryAndMissingPathDoesNotCreateDirectory() async throws {
        let workspace = makeTempWorkspace()
        let nested = workspace.path("nested/deeper")
        let store = LibraryStore(libraryURL: nested.appendingPathComponent("library.json"))

        XCTAssertTrue(store.isLoading)
        await waitForLibraryLoad(store)

        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.canEdit)
        XCTAssertTrue(store.tracks.isEmpty)
        XCTAssertEqual(store.revision, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: nested.path),
            "init 与载入都不得创建目录"
        )

        store.clearLibrary()
        store.clearLibrary()
        XCTAssertTrue(store.tracks.isEmpty)
        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertTrue(store.playlists.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.revision, 0, "空库 clear 不产生版本变化")

        // 只有真正写入时才创建目录。
        store.toggleFavorite(makeTestTrack(title: "First"))
        store.flushPendingSave()
        XCTAssertNil(store.saveErrorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }
}
