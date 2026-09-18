import Foundation
import XCTest

@testable import HarmonyPlayer

/// 歌词会话缓存与 FLAC 轻量歌词读取的测试。
/// 全部使用临时目录里现场合成的文件，不读取用户曲库。
final class LyricsCacheTests: XCTestCase {
    private var workspace: TempWorkspace!

    override func setUp() {
        super.setUp()
        workspace = makeTempWorkspace()
        LyricsCache.shared.removeAll()
    }

    override func tearDown() {
        LyricsCache.shared.removeAll()
        workspace = nil
        super.tearDown()
    }

    // MARK: - FLAC 只读歌词路径

    /// 合成“fLaC 头 + 大块 PICTURE（在注释块之前）+ VORBIS_COMMENT（末块）”，
    /// 验证只读歌词路径会 seek 跳过封面块并正确拿到 LYRICS。
    func testReadLyricsSkipsPictureBlock() throws {
        let comments = ["TITLE=测试曲", "LYRICS=[00:01.00]第一句\n[00:02.50]第二句"]
        let data = makeSyntheticFLAC(comments: comments, picturePayloadBytes: 100_000)
        let url = workspace.path("with-picture.flac")
        try data.write(to: url)

        let lyrics = EmbeddedMetadataReader.readLyrics(from: url)
        XCTAssertEqual(lyrics, comments[1].split(separator: "=", maxSplits: 1).last.map(String.init))
    }

    /// 没有注释块时返回 nil，而不是崩溃或读到垃圾。
    func testReadLyricsReturnsNilWithoutCommentBlock() throws {
        // fLaC 签名后只有一个空的 STREAMINFO 占位块（type 0），没有注释块。
        var data = Data("fLaC".utf8)
        data.append(contentsOf: [0x80, 0x00, 0x00, 0x00])
        let url = workspace.path("no-comments.flac")
        try data.write(to: url)

        XCTAssertNil(EmbeddedMetadataReader.readLyrics(from: url))
        XCTAssertNil(EmbeddedMetadataReader.readLyrics(from: workspace.path("not-flac.mp3")))
    }

    // MARK: - LyricsCache

    /// 同名 .lrc 存在时加载成功，之后立即同步命中 .ready。
    func testLoadSidecarLRCAndImmediateHit() async throws {
        let url = workspace.path("sidecar-song.flac")
        try Data("garbage-not-a-real-flac".utf8).write(to: url)
        let lrc = """
        [00:01.00]第一句歌词
        [00:03.20]第二句歌词
        """
        try lrc.write(to: workspace.path("sidecar-song.lrc"), atomically: true, encoding: .utf8)

        let track = makeTestTrack(
            id: testUUID(0xA001),
            title: "sidecar",
            directory: workspace.root.path,
            fileName: "sidecar-song.flac"
        )

        let lines = await LyricsCache.shared.load(track: track).value
        XCTAssertEqual(lines?.count, 2)
        XCTAssertEqual(lines?.first?.text, "第一句歌词")

        guard case .ready(let cached) = LyricsCache.shared.immediateResult(for: track.id) else {
            return XCTFail("加载完成后应能同步命中 .ready")
        }
        XCTAssertEqual(cached.map(\.text), ["第一句歌词", "第二句歌词"])
    }

    /// 确认没有歌词的曲目缓存为 .missing，第二次读取也不会重新报“加载中”。
    func testMissingLyricsCachedAsMissing() async throws {
        let comments = ["TITLE=纯音乐"]
        let data = makeSyntheticFLAC(comments: comments, picturePayloadBytes: 0)
        let url = workspace.path("instrumental.flac")
        try data.write(to: url)

        let track = makeTestTrack(
            id: testUUID(0xA002),
            title: "instrumental",
            directory: workspace.root.path,
            fileName: "instrumental.flac"
        )

        let lines = await LyricsCache.shared.load(track: track).value
        XCTAssertNil(lines)
        guard case .missing = LyricsCache.shared.immediateResult(for: track.id) else {
            return XCTFail("无歌词曲目应缓存为 .missing")
        }
    }

    func testRemoveAllClearsCachedState() async throws {
        let url = workspace.path("clear-song.flac")
        try Data("garbage".utf8).write(to: url)
        try "[00:01.00]会被清掉".write(
            to: workspace.path("clear-song.lrc"),
            atomically: true,
            encoding: .utf8
        )

        let track = makeTestTrack(
            id: testUUID(0xA003),
            title: "clear",
            directory: workspace.root.path,
            fileName: "clear-song.flac"
        )

        _ = await LyricsCache.shared.load(track: track).value
        XCTAssertNotNil(LyricsCache.shared.immediateResult(for: track.id))

        LyricsCache.shared.removeAll()
        XCTAssertNil(LyricsCache.shared.immediateResult(for: track.id))
    }

    // MARK: - 合成 FLAC

    /// 组装最小 FLAC 字节流：可选的 PICTURE 块（用零填充，测试 seek 跳过），
    /// 最后跟一个 VORBIS_COMMENT 块。仅用于喂给本项目自己的轻量解析器。
    private func makeSyntheticFLAC(comments: [String], picturePayloadBytes: Int) -> Data {
        var data = Data("fLaC".utf8)

        if picturePayloadBytes > 0 {
            // type 6，非末块，长度 24 位大端。
            data.append(contentsOf: [0x06])
            data.append(contentsOf: encodeUInt24BE(picturePayloadBytes))
            data.append(contentsOf: [UInt8](repeating: 0, count: picturePayloadBytes))
        }

        var commentPayload = Data()
        let vendor = Data("HarmonyPlayerTests".utf8)
        commentPayload.append(contentsOf: encodeUInt32LE(UInt32(vendor.count)))
        commentPayload.append(vendor)
        commentPayload.append(contentsOf: encodeUInt32LE(UInt32(comments.count)))
        for comment in comments {
            let bytes = Data(comment.utf8)
            commentPayload.append(contentsOf: encodeUInt32LE(UInt32(bytes.count)))
            commentPayload.append(bytes)
        }

        // type 4，末块（0x80 | 4 = 0x84）。
        data.append(contentsOf: [0x84])
        data.append(contentsOf: encodeUInt24BE(commentPayload.count))
        data.append(commentPayload)
        return data
    }

    private func encodeUInt32LE(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
    }

    private func encodeUInt24BE(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }
}
