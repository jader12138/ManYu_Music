import AppKit
import Foundation
import ImageIO

/// Fixed pixel tiers for cover art. Views pick the smallest tier that still
/// covers `pointSize * displayScale`, so a 44pt list row never decodes a 3000px
/// cover, and the cache key space stays bounded to three sizes per file.
enum ArtworkPixelTier: Int, CaseIterable, Hashable, Sendable {
    case small = 128
    case medium = 384
    case large = 768

    var pixels: Int { rawValue }

    static func tier(for pointSize: CGFloat, displayScale: CGFloat) -> ArtworkPixelTier {
        normalize(Int((max(1, pointSize) * max(1, displayScale)).rounded(.up)))
    }

    /// Snaps any requested pixel size onto a tier, so arbitrary sizes can never
    /// produce unbounded cache keys.
    static func normalize(_ pixelSize: Int) -> ArtworkPixelTier {
        allCases.first { $0.pixels >= pixelSize } ?? .large
    }
}

/// ImageIO downsampling. Always decodes exactly one bitmap at the requested size
/// and never falls back to a full-size original.
enum ArtworkImageDecoder {
    static func makeImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard !data.isEmpty, maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Deliberately no `CGImageSourceCreateImageAtIndex` fallback: decoding the
            // original here would blow past the cache's cost budget.
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Reads only the container header, so candidate probing never decodes pixels.
    static func pixelSize(of data: Data) -> CGSize? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

/// Bounded TTL set for "this file has no artwork". Expired entries stop counting,
/// and unexpired entries are hard-capped to the newest `limit` ones.
struct ArtworkMissingCache {
    let limit: Int
    let ttl: TimeInterval
    private var entries: [String: Date] = [:]

    init(limit: Int, ttl: TimeInterval) {
        self.limit = max(1, limit)
        self.ttl = ttl
    }

    var count: Int { entries.count }

    mutating func contains(_ key: String, now: Date = Date()) -> Bool {
        guard let date = entries[key] else { return false }
        guard now.timeIntervalSince(date) < ttl else {
            entries[key] = nil
            return false
        }
        return true
    }

    mutating func markMissing(_ key: String, now: Date = Date()) {
        entries[key] = now
        guard entries.count > limit else { return }
        var trimmed: [String: Date] = [:]
        for entry in entries.sorted(by: { $0.value > $1.value }).prefix(limit) {
            trimmed[entry.key] = entry.value
        }
        entries = trimmed
    }

    mutating func clear(_ key: String) {
        entries[key] = nil
    }
}

/// Bounds how many metadata reads / decodes may run at once. Waiting is
/// cancellable: a cancelled waiter leaves the queue immediately and throws
/// `CancellationError`, so scrolled-away rows stop occupying the queue.
private actor AsyncLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async throws {
        if Task.isCancelled {
            throw CancellationError()
        }
        if active < limit {
            active += 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Runs while the actor is still isolated, so a cancellation can never
                // slip past registration: it either resumes here or via cancelWaiter.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Callers must pair every successful `acquire` with exactly one `release`.
    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            // Hand the slot over directly so `active` stays unchanged.
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Cover art pipeline: caches per URL + tier, coalesces identical requests by
/// reference count, cancels a shared load once its last waiter goes away, caps
/// concurrent metadata reads, and briefly remembers "no artwork" results.
actor ArtworkPipeline {
    static let shared = ArtworkPipeline()

    private struct InFlight {
        let task: Task<NSImage?, Never>
        var waiters: Set<UUID>
    }

    private let limiter = AsyncLimiter(limit: 4)
    private var inFlight: [String: InFlight] = [:]
    private var missing = ArtworkMissingCache(limit: 512, ttl: 120)

    /// Observable for tests: size of the negative cache.
    var missingCount: Int { missing.count }

    func artwork(for track: Track, pixelSize: Int) async -> NSImage? {
        let url = track.url
        let tier = ArtworkPixelTier.normalize(pixelSize)
        let key = ArtworkCache.key(for: url, tier: tier)

        if let cached = ArtworkCache.shared.image(for: url, tier: tier) {
            return cached
        }
        if missing.contains(url.path) {
            return nil
        }

        let waiterID = UUID()
        let task: Task<NSImage?, Never>
        if var entry = inFlight[key] {
            entry.waiters.insert(waiterID)
            inFlight[key] = entry
            task = entry.task
        } else {
            // Unstructured task: cancelling one caller never cancels the others, and
            // every remaining waiter still receives the finished image.
            task = Task<NSImage?, Never> { [weak self] in
                guard let self else { return nil }
                return await self.load(track: track, tier: tier)
            }
            inFlight[key] = InFlight(task: task, waiters: [waiterID])
        }

        defer { releaseWaiter(waiterID, key: key) }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.releaseWaiter(waiterID, key: key) }
        }
    }

    /// Drops one waiter. The last one to leave cancels a load that has not
    /// produced anything yet, so scrolled-away rows do not keep reading files.
    private func releaseWaiter(_ waiterID: UUID, key: String) {
        guard var entry = inFlight[key] else { return }
        guard entry.waiters.remove(waiterID) != nil else { return }
        if entry.waiters.isEmpty {
            inFlight[key] = nil
            entry.task.cancel()
        } else {
            inFlight[key] = entry
        }
    }

    private func load(track: Track, tier: ArtworkPixelTier) async -> NSImage? {
        do {
            try await limiter.acquire()
        } catch {
            return nil
        }

        // From here on there is no throwing call, so the single `release` below is
        // guaranteed to run (defer equivalent) even when this task is cancelled.
        let image: NSImage?
        if Task.isCancelled {
            image = nil
        } else {
            image = await AudioMetadataLoader.decodeArtwork(for: track, pixelSize: tier.pixels)
        }
        await limiter.release()

        if let image {
            ArtworkCache.shared.insert(image, for: track.url, tier: tier)
            missing.clear(track.url.path)
        } else if !Task.isCancelled {
            // A cancelled read must never be recorded as "this file has no artwork".
            missing.markMissing(track.url.path)
        }
        return image
    }
}
