import AppKit
import Combine
import Foundation
import XCTest

@testable import HarmonyPlayer

/// 资料库来源（文件夹/文件）的移除契约：
/// 移除一个来源后，由该来源导入的曲目必须一并从资料库删除，
/// 且来源列表与持久化文件保持一致。
///
/// 用例通过生成最小合法 WAV（PCM）文件来获得真实可导入的音频，
/// 不读取用户音乐目录。
@MainActor
final class LibrarySourceRemovalTests: XCTestCase {

    // MARK: - 工具

    /// 生成一段指定时长（秒）的 16-bit 单声道 8kHz PCM WAV。
    private func writeWAV(to url: URL, seconds: Double = 2) throws {
        let sampleRate = 8000
        let frameCount = Int(seconds * Double(sampleRate))
        let dataSize = frameCount * 2
        var header = Data()
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: Array("RIFF".utf8))
        appendLE(UInt32(36 + dataSize))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        appendLE(UInt32(16))            // PCM chunk size
        appendLE(UInt16(1))             // PCM
        appendLE(UInt16(1))             // mono
        appendLE(UInt32(sampleRate))
        appendLE(UInt32(sampleRate * 2))
        appendLE(UInt16(2))
        appendLE(UInt16(16))
        header.append(contentsOf: Array("data".utf8))
        appendLE(UInt32(dataSize))

        let silence = Data(count: dataSize)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try header.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(silence)
        try handle.close()
    }

    private func waitForImport(_ store: LibraryStore, timeout: TimeInterval = 15) async {
        var cancellable: AnyCancellable?
        let done = expectation(description: "导入结束")
        if !store.isImporting {
            // 已结束也要让 add 的 Task 有机会启动。
            try? await Task.sleep(for: .milliseconds(100))
            if !store.isImporting { return }
        }
        cancellable = store.$isImporting
            .filter { !$0 }
            .prefix(1)
            .sink { _ in done.fulfill() }
        await fulfillment(of: [done], timeout: timeout)
        cancellable?.cancel()
    }

    // MARK: - 用例

    /// 导入一个含两首歌的文件夹，再移除该来源：曲目必须全部消失。
    func testRemoveFolderSourceRemovesItsTracks() async throws {
        let workspace = makeTempWorkspace()
        let folder = try workspace.makeDirectory("music/专辑甲")
        try writeWAV(to: folder.appendingPathComponent("a.wav"))
        try writeWAV(to: folder.appendingPathComponent("b.wav"))

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)

        let top = folder.deletingLastPathComponent()  // .../music
        store.add(urls: [top])
        await waitForImport(store)

        XCTAssertEqual(store.tracks.count, 2, "文件夹中两首 WAV 应被导入")
        XCTAssertEqual(store.sources.count, 1)
        let source = try XCTUnwrap(store.sources.first)
        XCTAssertTrue(source.isDirectory)

        store.removeLibrarySource(source)
        XCTAssertEqual(store.tracks.count, 0, "移除文件夹来源后，其下所有歌曲必须一并删除")
        XCTAssertTrue(store.sources.isEmpty)
        store.flushPendingSave()

        // 落盘文件也不应再包含这些曲目。
        let persisted = try decodeLibraryFile(Data(contentsOf: workspace.libraryURL))
        XCTAssertTrue(persisted.tracks.isEmpty)
    }

    /// 两个文件夹各含歌曲，移除其中一个，另一个的歌曲必须保留。
    func testRemoveOneFolderKeepsOtherFoldersTracks() async throws {
        let workspace = makeTempWorkspace()
        let folderA = try workspace.makeDirectory("music/专辑甲")
        let folderB = try workspace.makeDirectory("music/专辑乙")
        try writeWAV(to: folderA.appendingPathComponent("a.wav"))
        try writeWAV(to: folderB.appendingPathComponent("b.wav"))

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)

        store.add(urls: [folderA, folderB])
        await waitForImport(store)
        XCTAssertEqual(store.tracks.count, 2)

        let sourceA = try XCTUnwrap(store.sources.first { $0.url == folderA.standardizedFileURL })
        store.removeLibrarySource(sourceA)

        XCTAssertEqual(store.tracks.count, 1, "只应删除被移除来源下的歌曲")
        XCTAssertEqual(store.tracks.first?.url.lastPathComponent, "b.wav")
        XCTAssertEqual(store.sources.count, 1)
    }

    /// 来源必须跨重启持久化：重启后来源列表应恢复，且不重复导入。
    func testSourcesPersistAcrossRelaunch() async throws {
        let workspace = makeTempWorkspace()
        let folder = try workspace.makeDirectory("music/专辑甲")
        try writeWAV(to: folder.appendingPathComponent("a.wav"))

        do {
            let store = LibraryStore(libraryURL: workspace.libraryURL)
            await waitForLibraryLoad(store)
            store.add(urls: [folder])
            await waitForImport(store)
            XCTAssertEqual(store.tracks.count, 1)
            store.flushPendingSave()
        }

        let reopened = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(reopened)
        XCTAssertEqual(reopened.tracks.count, 1)
        XCTAssertEqual(reopened.sources.count, 1, "来源应随 library.json 持久化并在重启后恢复")
        XCTAssertEqual(reopened.sources.first?.url, folder.standardizedFileURL)
        XCTAssertTrue(reopened.sources.first?.isDirectory == true)
    }

    /// 模拟真实场景：歌曲由旧版本导入（已在 JSON 中，且旧 JSON 没有 sources），
    /// 本次会话重新添加同一文件夹（无新曲），再移除来源——已有歌曲必须被删掉。
    func testRemoveSourceWhenTracksCameFromLegacyLibrary() async throws {
        let workspace = makeTempWorkspace()
        let folder = try workspace.makeDirectory("music/专辑甲")
        let songURL = folder.appendingPathComponent("a.wav")
        try writeWAV(to: songURL)

        // 旧版本库：只有 tracks/favoriteIDs，没有 sources。
        let legacyTrack = Track(
            url: songURL, title: "旧曲", artist: "旧艺人", album: "旧专辑", duration: 2
        )
        try workspace.write(
            try encodeLegacyLibraryJSON(tracks: [legacyTrack], favoriteIDs: []),
            to: "library.json"
        )

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)
        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertTrue(store.sources.isEmpty, "旧 JSON 没有 sources，启动后来源为空")

        // 用户通过面板重新选中同一文件夹（与 add(urls:) 同一路径）。
        store.add(urls: [folder])
        await waitForImport(store)
        XCTAssertEqual(store.tracks.count, 1, "没有新曲，不应重复导入")
        XCTAssertEqual(store.sources.count, 1)

        store.removeLibrarySource(try XCTUnwrap(store.sources.first))
        XCTAssertEqual(store.tracks.count, 0, "即使歌曲来自旧库，移除来源时也必须删除")
    }

    /// 歌曲以真实路径存在于旧库中，用户本次通过指向该目录的软链（Finder 别名等场景）
    /// 选中来源并移除：归一化后应能匹配并删除歌曲。
    func testRemoveSourceWithSymlinkedPath() async throws {
        let workspace = makeTempWorkspace()
        let realFolder = try workspace.makeDirectory("real/专辑甲")
        let songURL = realFolder.appendingPathComponent("a.wav")
        try writeWAV(to: songURL)

        try workspace.write(
            try encodeLegacyLibraryJSON(
                tracks: [Track(url: songURL, title: "旧曲", artist: "甲", album: "辑", duration: 2)],
                favoriteIDs: []
            ),
            to: "library.json"
        )

        // 面板/拖拽拿到的是指向真实目录的软链路径。
        let linkFolder = workspace.path("link-to-album")
        try FileManager.default.createSymbolicLink(
            at: linkFolder, withDestinationURL: realFolder
        )

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)
        XCTAssertEqual(store.tracks.count, 1)

        store.add(urls: [linkFolder])
        await waitForImport(store)
        XCTAssertEqual(store.sources.first?.url, linkFolder.standardizedFileURL)

        store.removeLibrarySource(try XCTUnwrap(store.sources.first))
        XCTAssertEqual(store.tracks.count, 0, "来源是软链路径时也应删掉其下歌曲")
    }

    /// 核心回归：添加文件夹后导入仍在进行时立即移除来源，
    /// 在途导入落库绝不允许把这些歌曲"复活"。
    func testRemoveSourceWhileImportIsInFlightNeverResurrects() async throws {
        let workspace = makeTempWorkspace()
        let folder = try workspace.makeDirectory("music/大专辑")
        for index in 0..<12 {
            try writeWAV(to: folder.appendingPathComponent("song-\(index).wav"))
        }

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)

        store.add(urls: [folder])

        // 等到导入任务真正启动后立刻移除来源（模拟用户快速点"−"）。
        let start = ContinuousClock.now
        while !store.isImporting, ContinuousClock.now < start.advanced(by: .seconds(2)) {
            await Task.yield()
        }
        XCTAssertTrue(store.isImporting, "测试前置：导入应处于进行中")
        XCTAssertEqual(store.sources.count, 1)
        store.removeLibrarySource(try XCTUnwrap(store.sources.first))
        XCTAssertTrue(store.sources.isEmpty)

        await waitForImport(store)
        XCTAssertEqual(store.tracks.count, 0, "导入结束后被移除来源的歌曲绝不能出现")
        store.flushPendingSave()
        let persisted = try decodeLibraryFile(Data(contentsOf: workspace.libraryURL))
        XCTAssertTrue(persisted.tracks.isEmpty, "复活保护必须落到磁盘")
    }

    /// 移除来源时，被删歌曲的收藏/播放历史/歌单引用也应一并清理。
    func testRemoveSourceCleansFavoriteHistoryAndPlaylists() async throws {
        let workspace = makeTempWorkspace()
        let folder = try workspace.makeDirectory("music/专辑甲")
        try writeWAV(to: folder.appendingPathComponent("a.wav"))

        let store = LibraryStore(libraryURL: workspace.libraryURL)
        await waitForLibraryLoad(store)
        store.add(urls: [folder])
        await waitForImport(store)

        let track = try XCTUnwrap(store.tracks.first)
        store.toggleFavorite(track)
        store.recordPlay(track)
        let playlist = store.createPlaylist(named: "我的歌单")
        store.add(track, to: playlist.id)

        let source = try XCTUnwrap(store.sources.first)
        store.removeLibrarySource(source)

        XCTAssertTrue(store.tracks.isEmpty)
        XCTAssertTrue(store.favoriteIDs.isEmpty, "被删歌曲不应留在收藏中")
        XCTAssertTrue(store.history.isEmpty, "被删歌曲不应留在播放历史中")
        XCTAssertTrue(store.playlists.allSatisfy { $0.trackIDs.isEmpty }, "歌单中不应残留被删歌曲")
    }
}
