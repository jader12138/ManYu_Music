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

    /// 只读歌词的轻量路径：FLAC 规范只允许一个 VORBIS_COMMENT 块，
    /// 解析到该块即可结束遍历；封面（PICTURE）等大块一律 seek 跳过，
    /// 不把几 MB 的图片数据读进内存。供启动批量预热歌词使用。
    static func readLyrics(from url: URL) -> String? {
        guard url.pathExtension.lowercased() == "flac" else { return nil }
        return readFLACLyrics(from: url)
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
