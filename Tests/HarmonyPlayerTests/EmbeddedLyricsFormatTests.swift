import Foundation
import XCTest

@testable import HarmonyPlayer

/// 内嵌歌词按格式分发：FLAC 读 Vorbis、MP3 读 ID3v2 USLT、MP4 读 moov.udta.©lyr。
/// 这里只覆盖 MP3 / MP4 两类自家解析；FLAC 已有既有覆盖。
final class EmbeddedLyricsFormatTests: XCTestCase {

    // MARK: - MP3 / ID3v2

    func testMP3ID3v4USLTLyrics() throws {
        let workspace = makeTempWorkspace()
        let lyrics = "[00:01.00]漫域第一行\n[00:03.50]漫域第二行\n"
        let mp3 = makeMP3(majorVersion: 4, lyrics: lyrics, encoding: 3)
        try workspace.write(mp3, to: "song.mp3")

        let result = EmbeddedMetadataReader.readLyrics(from: workspace.path("song.mp3"))
        XCTAssertEqual(result, lyrics)
    }

    func testMP3ID3v3USLTLyrics() throws {
        let workspace = makeTempWorkspace()
        let lyrics = "纯文本歌词没有时间戳"
        let mp3 = makeMP3(majorVersion: 3, lyrics: lyrics, encoding: 3)
        try workspace.write(mp3, to: "song.mp3")

        let result = EmbeddedMetadataReader.readLyrics(from: workspace.path("song.mp3"))
        XCTAssertEqual(result, lyrics)
    }

    func testMP3USLTUTF16WithBOM() throws {
        let workspace = makeTempWorkspace()
        let lyrics = "[00:02.00]中文歌词测试"
        let mp3 = makeMP3(majorVersion: 4, lyrics: lyrics, encoding: 1)
        try workspace.write(mp3, to: "song.mp3")

        let result = EmbeddedMetadataReader.readLyrics(from: workspace.path("song.mp3"))
        XCTAssertEqual(
            result?.trimmingCharacters(in: .whitespacesAndNewlines),
            lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testMP3WithoutID3ReturnsNil() throws {
        let workspace = makeTempWorkspace()
        // 没有 ID3v2 头的裸数据。
        try workspace.write(Data([0xFF, 0xFB, 0x90, 0x00, 0x01, 0x02]), to: "raw.mp3")
        XCTAssertNil(EmbeddedMetadataReader.readLyrics(from: workspace.path("raw.mp3")))
    }

    // MARK: - MP4 / QuickTime

    func testMP4LyricsAtom() throws {
        let workspace = makeTempWorkspace()
        let lyrics = "[00:05.00]漫域 MP4 歌词\n[00:08.00]第二行"
        let mp4 = makeMP4(lyrics: lyrics)
        try workspace.write(mp4, to: "song.m4a")

        let result = EmbeddedMetadataReader.readLyrics(from: workspace.path("song.m4a"))
        XCTAssertEqual(result, lyrics)
    }

    func testMP4InMP4Container() throws {
        let workspace = makeTempWorkspace()
        let lyrics = "mp4 扩展名也行"
        let mp4 = makeMP4(lyrics: lyrics)
        try workspace.write(mp4, to: "song.mp4")

        let result = EmbeddedMetadataReader.readLyrics(from: workspace.path("song.mp4"))
        XCTAssertEqual(result, lyrics)
    }

    func testMP4WithoutLyricsReturnsNil() throws {
        let workspace = makeTempWorkspace()
        let mp4 = makeMP4(lyrics: nil)
        try workspace.write(mp4, to: "song.m4a")
        XCTAssertNil(EmbeddedMetadataReader.readLyrics(from: workspace.path("song.m4a")))
    }

    // MARK: - 分发兜底

    func testUnsupportedExtensionReturnsNil() throws {
        let workspace = makeTempWorkspace()
        try workspace.write(Data([0x00, 0x01, 0x02]), to: "song.wav")
        XCTAssertNil(EmbeddedMetadataReader.readLyrics(from: workspace.path("song.wav")))
    }

    // MARK: - 构造辅助

    /// 构造含 USLT 帧的 ID3v2 文件（version 3 或 4）。
    private func makeMP3(majorVersion: UInt8, lyrics: String, encoding: UInt8) -> Data {
        let textData: Data
        switch encoding {
        case 1: // UTF-16 with BOM
            textData = utf16BEWithBOM(lyrics)
        case 3:
            textData = Data(lyrics.utf8)
        default:
            textData = lyrics.data(using: .isoLatin1) ?? Data(lyrics.utf8)
        }

        // USLT payload: encoding(1) + language(3) + descriptor(null) + text
        var payload = Data()
        payload.append(encoding)
        payload.append("eng".data(using: .ascii)!)
        // descriptor 为空 + null 结尾；UTF-16 编码用双字节 null。
        switch encoding {
        case 1, 2: payload.append(Data([0, 0]))
        default: payload.append(0)
        }
        payload.append(textData)

        // frame: ID(4) + size(4) + flags(2) + payload
        var frame = Data("USLT".utf8)
        let frameSize = UInt32(payload.count)
        if majorVersion == 4 {
            frame.append(synchsafe(frameSize))
        } else {
            frame.append(beUInt32(frameSize))
        }
        frame.append(Data([0, 0])) // flags
        frame.append(payload)

        // header: "ID3" + version(2) + flags(1) + tag size(synchsafe)
        var header = Data("ID3".utf8)
        header.append(majorVersion)
        header.append(0) // revision
        header.append(0) // flags
        header.append(synchsafe(UInt32(frame.count)))

        var file = header
        file.append(frame)
        // 假 MPEG 帧让文件像 MP3（解析不依赖它）。
        file.append(Data([0xFF, 0xFB, 0x90, 0x44, 0x00, 0x00, 0x00, 0x00]))
        return file
    }

    /// 构造最小 MP4：ftyp + moov{udta{meta{ilst{©lyr}}}}。
    /// lyrics 为 nil 时不嵌 ©lyr，模拟无歌词文件。
    private func makeMP4(lyrics: String?) -> Data {
        var file = Data()
        // ftyp
        file.append(atom(type: "ftyp", payload: Data("M4A ".utf8) + Data([0]) + Data("M4A ".utf8)))

        var moovPayload = Data()
        if let lyrics {
            var lyrPayload = Data([0, 0, 0, 0, 0, 0, 0, 1]) // version+flags=1(UTF-8 text)+reserved
            lyrPayload.append(Data(lyrics.utf8))
            let lyrAtom = atom(type: Data([0xA9, 0x6C, 0x79, 0x72]), payload: lyrPayload)
            let ilst = atom(type: "ilst", payload: lyrAtom)
            let meta = atom(type: "meta", payload: ilst)
            let udta = atom(type: "udta", payload: meta)
            moovPayload.append(udta)
        }
        file.append(atom(type: "moov", payload: moovPayload))
        return file
    }

    private func atom(type: Data, payload: Data) -> Data {
        var d = Data()
        d.append(beUInt32(UInt32(8 + payload.count)))
        d.append(type)
        d.append(payload)
        return d
    }

    private func atom(type: String, payload: Data) -> Data {
        atom(type: Data(type.utf8), payload: payload)
    }

    /// UTF-16BE + BOM（FE FF）。
    private func utf16BEWithBOM(_ s: String) -> Data {
        var d = Data([0xFE, 0xFF])
        for scalar in s.unicodeScalars {
            let v = scalar.value
            d.append(UInt8((v >> 8) & 0xFF))
            d.append(UInt8(v & 0xFF))
        }
        return d
    }

    private func synchsafe(_ value: UInt32) -> Data {
        var d = Data(count: 4)
        d[0] = UInt8((value >> 21) & 0x7F)
        d[1] = UInt8((value >> 14) & 0x7F)
        d[2] = UInt8((value >> 7) & 0x7F)
        d[3] = UInt8(value & 0x7F)
        return d
    }

    private func beUInt32(_ value: UInt32) -> Data {
        var d = Data(count: 4)
        d[0] = UInt8((value >> 24) & 0xFF)
        d[1] = UInt8((value >> 16) & 0xFF)
        d[2] = UInt8((value >> 8) & 0xFF)
        d[3] = UInt8(value & 0xFF)
        return d
    }
}
