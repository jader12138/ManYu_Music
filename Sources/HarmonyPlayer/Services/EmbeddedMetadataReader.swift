import Foundation

struct EmbeddedAudioMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var lyrics: String?
    var artworkData: Data?
}

enum EmbeddedMetadataReader {
    static func read(from url: URL) -> EmbeddedAudioMetadata? {
        switch url.pathExtension.lowercased() {
        case "flac":
            return readFLAC(from: url)
        default:
            return nil
        }
    }

    /// 只读歌词的轻量路径：按容器格式分发，FLAC 读 VORBIS_COMMENT、
    /// MP3 读 ID3v2 的 USLT frame、MP4 家族读 moov.udta.©lyr atom。
    /// 不支持的格式返回 nil，交由上层 AVFoundation 兜底。
    /// 封面等大块一律 seek 跳过，不把几 MB 的图片数据读进内存。
    /// 供启动批量预热歌词使用。
    static func readLyrics(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "flac":
            return readFLACLyrics(from: url)
        case "mp3":
            return readMP3Lyrics(from: url)
        case "m4a", "m4b", "mp4", "mov":
            return readMP4Lyrics(from: url)
        default:
            return nil
        }
    }

    private static func readFLAC(from url: URL) -> EmbeddedAudioMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let signature = try? readExactly(handle, count: 4),
              signature == Data("fLaC".utf8) else {
            return nil
        }

        var result = EmbeddedAudioMetadata()
        var reachedLastBlock = false

        while !reachedLastBlock {
            guard let header = try? readExactly(handle, count: 4), header.count == 4 else {
                break
            }

            let blockType = header[0] & 0x7f
            reachedLastBlock = (header[0] & 0x80) != 0
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])

            guard length >= 0, length < 256 * 1024 * 1024 else { break }

            switch blockType {
            case 4:
                guard let payload = try? readExactly(handle, count: length) else { return result }
                parseVorbisComments(payload, into: &result)
            case 6:
                guard let payload = try? readExactly(handle, count: length) else { return result }
                if result.artworkData == nil {
                    result.artworkData = parsePictureBlock(payload)
                }
            default:
                guard (try? skip(handle, count: length)) != nil else { return result }
            }
        }

        return result
    }

    private static func readFLACLyrics(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let signature = try? readExactly(handle, count: 4),
              signature == Data("fLaC".utf8) else {
            return nil
        }

        var reachedLastBlock = false

        while !reachedLastBlock {
            guard let header = try? readExactly(handle, count: 4), header.count == 4 else {
                break
            }

            let blockType = header[0] & 0x7f
            reachedLastBlock = (header[0] & 0x80) != 0
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])

            guard length >= 0, length < 256 * 1024 * 1024 else { break }

            switch blockType {
            case 4:
                // 唯一的 VORBIS_COMMENT 块：取出歌词即可结束，无需再遍历后续封面块。
                guard let payload = try? readExactly(handle, count: length) else { return nil }
                var metadata = EmbeddedAudioMetadata()
                parseVorbisComments(payload, into: &metadata)
                return metadata.lyrics
            default:
                // 封面等其他块只移动文件偏移，不读取内容。
                guard (try? skip(handle, count: length)) != nil else { return nil }
            }
        }

        return nil
    }

    // MARK: - MP3 / ID3v2 内嵌歌词

    private static func readMP3Lyrics(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // ID3v2 头：10 字节。前 3 字节 "ID3"，主版本 1 字节，修订 1 字节，flags 1 字节，size 4 字节（synchsafe）。
        guard let header = try? readExactly(handle, count: 10), header.count == 10 else { return nil }
        guard header.prefix(3) == Data("ID3".utf8) else { return nil }

        let majorVersion = header[3]
        // 只支持 ID3v2.3 / 2.4；2.2 用 3 字符帧 ID（ULT 而非 USLT），结构不同，跳过。
        guard majorVersion == 3 || majorVersion == 4 else { return nil }

        let tagSize = synchsafeInt(header, offset: 6)
        guard tagSize > 0, tagSize < 256 * 1024 * 1024 else { return nil }

        // 遍历帧直到命中 USLT 或读完 tag。
        var consumed = 0
        while consumed + 10 <= Int(tagSize) {
            guard let frameHeader = try? readExactly(handle, count: 10), frameHeader.count == 10 else { return nil }
            consumed += 10

            let frameID = frameHeader.prefix(4)
            // 全零帧 ID 表示 padding，tag 结束。
            if frameID == Data(repeating: 0, count: 4) { return nil }

            let frameSize: Int
            if majorVersion == 4 {
                // 2.4 帧大小也是 synchsafe。
                frameSize = Int(synchsafeInt(frameHeader, offset: 4))
            } else {
                // 2.3 用普通 4 字节大端。
                frameSize = Int(frameHeader[4]) << 24
                    | Int(frameHeader[5]) << 16
                    | Int(frameHeader[6]) << 8
                    | Int(frameHeader[7])
            }
            guard frameSize >= 0, frameSize < 256 * 1024 * 1024 else { return nil }
            consumed += frameSize

            if frameID == Data("USLT".utf8) {
                guard let payload = try? readExactly(handle, count: frameSize), payload.count == frameSize else { return nil }
                if let lyrics = parseUSLTFrame(payload) {
                    return lyrics
                }
                // 解析失败则继续找下一个（容错，极少有多个 USLT）。
            } else {
                guard (try? skip(handle, count: frameSize)) != nil else { return nil }
            }
        }
        return nil
    }

    /// USLT 帧：encoding(1) + language(3) + content descriptor(null-terminated) + 歌词文本。
    private static func parseUSLTFrame(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let encoding = data[0]
        // language 3 字节（如 "eng"）不校验。

        // descriptor 从偏移 4 开始，按编码以 null 结尾。
        var descEnd = 4
        switch encoding {
        case 0, 3: // ISO-8859-1 / UTF-8：单字节 null。
            while descEnd < data.count, data[descEnd] != 0 { descEnd += 1 }
            if descEnd < data.count { descEnd += 1 }
        case 1, 2: // UTF-16：双字节 null（对齐）。
            while descEnd + 1 < data.count, !(data[descEnd] == 0 && data[descEnd + 1] == 0) { descEnd += 2 }
            if descEnd + 1 < data.count { descEnd += 2 }
        default:
            return nil
        }

        guard descEnd <= data.count else { return nil }
        let textData = data.subdata(in: descEnd..<data.count)
        guard !textData.isEmpty else { return nil }
        return decodeText(textData, encoding: encoding)
    }

    /// ID3v2.4 的 synchsafe 整数：每字节只用低 7 位，共 28 位。
    private static func synchsafeInt(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return (UInt32(data[offset]) << 21)
            | (UInt32(data[offset + 1]) << 14)
            | (UInt32(data[offset + 2]) << 7)
            | UInt32(data[offset + 3])
    }

    /// 按 ID3 文本编码解析字节为字符串。
    private static func decodeText(_ data: Data, encoding: UInt8) -> String? {
        switch encoding {
        case 0: // ISO-8859-1
            return String(data: data, encoding: .isoLatin1)
        case 1: // UTF-16 with BOM
            return String(data: data, encoding: .utf16)
        case 2: // UTF-16BE without BOM
            // Swift 没有直接 UTF-16BE 编码，手动加 BOM 再解。
            let withBOM = Data([0xFE, 0xFF]) + data
            return String(data: withBOM, encoding: .utf16)
        case 3: // UTF-8
            return String(data: data, encoding: .utf8)
        default:
            return String(data: data, encoding: .utf8)
        }
    }

    // MARK: - MP4 / QuickTime 内嵌歌词

    private static func readMP4Lyrics(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // ©lyr 的 atom type 是 0xA96C7972（'©' 是 0xA9）。
        let lyrType = Data([0xA9, 0x6C, 0x79, 0x72])
        guard let payload = scanMP4Atom(handle: handle, targetType: lyrType) else { return nil }

        // iTunes 元数据 atom：前 8 字节是 version(1)+flags(3)+reserved(4)，之后为文本。
        // 判据：前 4 字节为 0（version/flags 区域）时跳过 8 字节头；否则直接当文本。
        var body = payload
        if payload.count >= 8,
           payload[0] == 0, payload[1] == 0, payload[2] == 0, payload[3] == 0 {
            body = payload.subdata(in: 8..<payload.count)
        }
        guard let text = String(data: body, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// 深度优先扫描 MP4 atom 树，返回第一个命中类型的 atom 的 data 负载。
    /// 遇容器（moov/udta/meta/ilst）下钻；trak 等大块容器不视为可下钻，直接 skip，
    /// 避免遍历整个轨道数据。
    private static func scanMP4Atom(
        handle: FileHandle,
        targetType: Data,
        limit: UInt64 = 256 * 1024 * 1024
    ) -> Data? {
        var consumed: UInt64 = 0
        while consumed + 8 <= limit {
            guard let header = try? readExactly(handle, count: 8), header.count == 8 else { return nil }
            consumed += 8

            let size = UInt32(header[0]) << 24
                | UInt32(header[1]) << 16
                | UInt32(header[2]) << 8
                | UInt32(header[3])
            let type = header.subdata(in: 4..<8)

            // size==0 表示 atom 延展到文件末尾；size==1 表示 64 位扩展大小（不支持）。
            guard size >= 8 else { return nil }
            let payloadSize = UInt64(size) - 8
            guard consumed + payloadSize <= limit else { return nil }

            if type == targetType {
                return try? readExactly(handle, count: Int(payloadSize))
            }

            if isMP4LyricsContainer(type) {
                // 递归扫描子树；未命中时子函数会读完整个 payload，指针在末尾。
                if let found = scanMP4Atom(handle: handle, targetType: targetType, limit: payloadSize) {
                    return found
                }
                consumed += payloadSize
            } else {
                guard (try? skip(handle, count: Int(payloadSize))) != nil else { return nil }
                consumed += payloadSize
            }
        }
        return nil
    }

    /// 只有这些容器可能包含 ©lyr，其他容器（trak/mdia/minf/stbl 等）直接跳过。
    private static func isMP4LyricsContainer(_ type: Data) -> Bool {
        return type == Data("moov".utf8)
            || type == Data("udta".utf8)
            || type == Data("meta".utf8)
            || type == Data("ilst".utf8)
    }

    private static func parseVorbisComments(
        _ payload: Data,
        into result: inout EmbeddedAudioMetadata
    ) {
        var offset = 0

        guard let vendorLength = readUInt32LE(payload, offset: &offset),
              skipBytes(payload, offset: &offset, count: Int(vendorLength)),
              let commentCount = readUInt32LE(payload, offset: &offset) else {
            return
        }

        for _ in 0..<Int(commentCount) {
            guard let byteCount = readUInt32LE(payload, offset: &offset),
                  let commentData = readData(payload, offset: &offset, count: Int(byteCount)),
                  let comment = String(data: commentData, encoding: .utf8),
                  let separator = comment.firstIndex(of: "=") else {
                return
            }

            let key = String(comment[..<separator])
            let value = String(comment[comment.index(after: separator)...])
            let normalizedKey = key
                .uppercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")

            switch normalizedKey {
            case "TITLE":
                if result.title == nil { result.title = value }
            case "ARTIST":
                if result.artist == nil { result.artist = value }
            case "ALBUMARTIST":
                if result.artist == nil { result.artist = value }
            case "ALBUM":
                if result.album == nil { result.album = value }
            case "LYRICS", "UNSYNCEDLYRICS", "UNSYNCEDLYRIC", "LYRIC":
                if result.lyrics == nil { result.lyrics = value }
            case "METADATA_BLOCK_PICTURE":
                if result.artworkData == nil,
                   let data = Data(base64Encoded: value) {
                    result.artworkData = parsePictureBlock(data)
                }
            case "COVERART", "COVERARTMIME":
                if normalizedKey == "COVERART",
                   result.artworkData == nil,
                   let data = Data(base64Encoded: value) {
                    result.artworkData = data
                }
            default:
                break
            }
        }
    }

    private static func parsePictureBlock(_ payload: Data) -> Data? {
        var offset = 0

        guard readUInt32BE(payload, offset: &offset) != nil,
              let mimeLength = readUInt32BE(payload, offset: &offset),
              skipBytes(payload, offset: &offset, count: Int(mimeLength)),
              let descriptionLength = readUInt32BE(payload, offset: &offset),
              skipBytes(payload, offset: &offset, count: Int(descriptionLength)),
              skipBytes(payload, offset: &offset, count: 16),
              let imageLength = readUInt32BE(payload, offset: &offset),
              let imageData = readData(payload, offset: &offset, count: Int(imageLength)),
              !imageData.isEmpty else {
            return nil
        }

        return imageData
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        guard count >= 0, let data = try handle.read(upToCount: count), data.count == count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    private static func skip(_ handle: FileHandle, count: Int) throws {
        guard count >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        if count == 0 { return }
        try handle.seek(toOffset: handle.offsetInFile + UInt64(count))
    }

    private static func readUInt32LE(_ data: Data, offset: inout Int) -> UInt32? {
        guard let bytes = readData(data, offset: &offset, count: 4) else { return nil }
        return bytes.enumerated().reduce(UInt32(0)) { value, item in
            value | UInt32(item.element) << UInt32(item.offset * 8)
        }
    }

    private static func readUInt32BE(_ data: Data, offset: inout Int) -> UInt32? {
        guard let bytes = readData(data, offset: &offset, count: 4) else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func skipBytes(_ data: Data, offset: inout Int, count: Int) -> Bool {
        guard count >= 0, offset + count <= data.count else { return false }
        offset += count
        return true
    }

    private static func readData(_ data: Data, offset: inout Int, count: Int) -> Data? {
        guard count >= 0, offset + count <= data.count else { return nil }
        let value = data.subdata(in: offset..<(offset + count))
        offset += count
        return value
    }
}
