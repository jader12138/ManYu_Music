import AppKit
import AVFoundation

enum AudioMetadataLoader {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc",
        "flac", "caf", "m4b", "mp4", "mov"
    ]

    static func makeTrack(
        from url: URL,
        id: UUID = UUID(),
        dateAdded: Date = .now
    ) async -> Track {
        let standardizedURL = url.standardizedFileURL
        let fallbackTitle = standardizedURL.deletingPathExtension().lastPathComponent
        let asset = AVURLAsset(url: standardizedURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        let embedded = await Task.detached(priority: .utility) {
            EmbeddedMetadataReader.read(from: standardizedURL)
        }.value

        let metadataTitle = await stringValue(for: .commonKeyTitle, in: metadata)
        let title = embedded?.title ?? metadataTitle

        var artist = embedded?.artist
        if artist == nil {
            artist = await stringValue(for: .commonKeyArtist, in: metadata)
        }
        if artist == nil {
            artist = await stringValue(for: .commonKeyAuthor, in: metadata)
        }

        let metadataAlbum = await stringValue(for: .commonKeyAlbumName, in: metadata)
        let album = embedded?.album ?? metadataAlbum

        // 音频技术参数：从首个音频轨道取 estimatedDataRate 与 AudioStreamBasicDescription
        let audioTech = await loadAudioTechParameters(from: asset)

        return Track(
            id: id,
            url: standardizedURL,
            title: title ?? fallbackTitle,
            artist: artist ?? "",
            album: album ?? "",
            duration: duration.isFinite ? max(0, duration) : 0,
            dateAdded: dateAdded,
            bitrate: audioTech.bitrate,
            sampleRate: audioTech.sampleRate,
            channels: audioTech.channels
        )
    }

    /// 从 AVAsset 的首个音频轨道读取比特率/采样率/声道数。
    /// - estimatedDataRate 单位是 bits per second；VBR 文件为平均值。
    /// - 采样率与声道数取自首个 CMAudioFormatDescription 的 AudioStreamBasicDescription。
    private static func loadAudioTechParameters(
        from asset: AVURLAsset
    ) async -> (bitrate: Int?, sampleRate: Int?, channels: Int?) {
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
              let audioTrack = audioTracks.first else {
            return (nil, nil, nil)
        }
        var bitrate: Int?
        var sampleRate: Int?
        var channels: Int?

        if let dataRate = try? await audioTrack.load(.estimatedDataRate), dataRate > 0 {
            bitrate = Int(dataRate.rounded())
        }

        let formatDescriptions = (try? await audioTrack.load(.formatDescriptions)) ?? []
        for desc in formatDescriptions {
            guard let audioDesc = desc as? CMAudioFormatDescription,
                  let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc) else { continue }
            let asbd = asbdPtr.pointee
            if sampleRate == nil, asbd.mSampleRate > 0 {
                sampleRate = Int(asbd.mSampleRate)
            }
            if channels == nil, asbd.mChannelsPerFrame > 0 {
                channels = Int(asbd.mChannelsPerFrame)
            }
            if sampleRate != nil && channels != nil { break }
        }

        return (bitrate, sampleRate, channels)
    }

    static func lyrics(for track: Track) async -> String? {
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
        if let lrc = try? String(contentsOf: lrcURL, encoding: .utf8),
           !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lrc
        }

        // 歌词只读路径：跳过 FLAC 封面块等 MB 级负载，批量预热全曲库时不读图片数据。
        let embedded = await Task.detached(priority: .utility) {
            EmbeddedMetadataReader.readLyrics(from: track.url)
        }.value
        if let lyrics = embedded,
           !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lyrics
        }

        let asset = AVURLAsset(url: track.url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        let lyricIdentifiers: [AVMetadataIdentifier] = [
            .iTunesMetadataLyrics,
            .id3MetadataUnsynchronizedLyric,
            .id3MetadataSynchronizedLyric
        ]

        for identifier in lyricIdentifiers {
            for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier) {
                if let value = await stringValue(of: item) {
                    return value
                }
            }
        }
        return nil
    }

    /// Cached, coalesced entry point. Defaults to the 768px tier, so the player and
    /// the home palette never decode a multi-thousand-pixel original.
    static func artwork(for track: Track, pixelSize: Int = ArtworkPixelTier.large.pixels) async -> NSImage? {
        await ArtworkPipeline.shared.artwork(for: track, pixelSize: pixelSize)
    }

    /// Raw read + decode. Runs off the main thread and decodes straight to
    /// `pixelSize` pixels instead of the original resolution.
    static func decodeArtwork(for track: Track, pixelSize: Int) async -> NSImage? {
        let embedded = await Task.detached(priority: .utility) {
            EmbeddedMetadataReader.read(from: track.url)
        }.value
        if let data = embedded?.artworkData,
           let image = ArtworkImageDecoder.makeImage(from: data, maxPixelSize: pixelSize) {
            return image
        }

        let asset = AVURLAsset(url: track.url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }

        let artworkIdentifiers: [AVMetadataIdentifier] = [
            .commonIdentifierArtwork,
            .quickTimeMetadataArtwork,
            .iTunesMetadataCoverArt,
            .id3MetadataAttachedPicture
        ]

        for identifier in artworkIdentifiers {
            for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier) {
                guard let data = try? await item.load(.dataValue) else { continue }
                if let image = ArtworkImageDecoder.makeImage(from: data, maxPixelSize: pixelSize) {
                    return image
                }
            }
        }

        // Some containers expose artwork under a format-specific key instead of commonKey.
        // Probe the header for dimensions first so non-image payloads are never decoded.
        for item in metadata {
            guard let data = try? await item.load(.dataValue),
                  let size = ArtworkImageDecoder.pixelSize(of: data),
                  size.width >= 80, size.height >= 80 else { continue }
            if let image = ArtworkImageDecoder.makeImage(from: data, maxPixelSize: pixelSize) {
                return image
            }
        }

        return nil
    }

    private static func stringValue(of item: AVMetadataItem) async -> String? {
        guard let rawValue = try? await item.load(.stringValue) else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func stringValue(
        for key: AVMetadataKey,
        in metadata: [AVMetadataItem]
    ) async -> String? {
        for item in metadata where item.commonKey == key {
            guard let rawValue = try? await item.load(.stringValue) else { continue }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return value
        }
        return nil
    }
}
