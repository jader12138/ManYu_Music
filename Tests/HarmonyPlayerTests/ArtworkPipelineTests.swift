import AppKit
import XCTest

@testable import HarmonyPlayer

/// 封面管线里纯逻辑 / 纯解码的部分。
/// 所有图片都在测试内用 CoreGraphics 现场生成，不读取仓库或用户目录里的任何资源。
final class ArtworkPipelineTests: XCTestCase {

    // MARK: 1. 解码降采样、不放大、无效输入

    func testDecoderDownsamplesToBudgetNeverEnlargesAndRejectsInvalidInput() throws {
        let large = try XCTUnwrap(makePNGData(width: 512, height: 512))
        let small = try XCTUnwrap(makePNGData(width: 64, height: 64))

        let smallTier = try XCTUnwrap(ArtworkImageDecoder.makeImage(from: large, maxPixelSize: 128))
        let smallSide = max(smallTier.size.width, smallTier.size.height)
        XCTAssertLessThanOrEqual(smallSide, 128, "不得超过请求的像素预算")
        XCTAssertLessThan(smallSide, 512, "必须真的降采样，而不是回退原图")

        let largeTier = try XCTUnwrap(ArtworkImageDecoder.makeImage(from: large, maxPixelSize: 384))
        let largeSide = max(largeTier.size.width, largeTier.size.height)
        XCTAssertLessThanOrEqual(largeSide, 384)
        XCTAssertGreaterThan(largeSide, smallSide, "请求的像素预算应当真正决定解码尺寸")

        let notEnlarged = try XCTUnwrap(ArtworkImageDecoder.makeImage(from: small, maxPixelSize: 128))
        XCTAssertLessThanOrEqual(
            max(notEnlarged.size.width, notEnlarged.size.height), 128,
            "源图比预算小时不得放大"
        )

        XCTAssertEqual(ArtworkImageDecoder.pixelSize(of: small), CGSize(width: 64, height: 64))
        XCTAssertEqual(ArtworkImageDecoder.pixelSize(of: large), CGSize(width: 512, height: 512))

        // 无效输入一律 nil，绝不回退到整图解码。
        XCTAssertNil(ArtworkImageDecoder.makeImage(from: Data(), maxPixelSize: 128))
        XCTAssertNil(ArtworkImageDecoder.makeImage(from: Data("not an image".utf8), maxPixelSize: 128))
        XCTAssertNil(ArtworkImageDecoder.makeImage(from: large, maxPixelSize: 0))
        XCTAssertNil(ArtworkImageDecoder.makeImage(from: large, maxPixelSize: -1))
        XCTAssertNil(ArtworkImageDecoder.pixelSize(of: Data()))
        XCTAssertNil(ArtworkImageDecoder.pixelSize(of: Data("not an image".utf8)))
    }

    // MARK: 2. tier 归一化

    func testPixelTierNormalizationSnapsToBoundedTiers() {
        XCTAssertEqual(ArtworkPixelTier.allCases.map(\.pixels), [128, 384, 768])

        XCTAssertEqual(ArtworkPixelTier.normalize(0), .small)
        XCTAssertEqual(ArtworkPixelTier.normalize(1), .small)
        XCTAssertEqual(ArtworkPixelTier.normalize(128), .small)
        XCTAssertEqual(ArtworkPixelTier.normalize(129), .medium)
        XCTAssertEqual(ArtworkPixelTier.normalize(384), .medium)
        XCTAssertEqual(ArtworkPixelTier.normalize(385), .large)
        XCTAssertEqual(ArtworkPixelTier.normalize(768), .large)
        XCTAssertEqual(ArtworkPixelTier.normalize(769), .large, "超出最大 tier 时钳到 large")
        XCTAssertEqual(ArtworkPixelTier.normalize(100_000), .large)

        XCTAssertEqual(ArtworkPixelTier.tier(for: 44, displayScale: 1), .small)
        XCTAssertEqual(ArtworkPixelTier.tier(for: 44, displayScale: 2), .small)
        XCTAssertEqual(ArtworkPixelTier.tier(for: 44, displayScale: 3), .medium)
        XCTAssertEqual(ArtworkPixelTier.tier(for: 300, displayScale: 2), .large)
        XCTAssertEqual(ArtworkPixelTier.tier(for: 0, displayScale: 0), .small, "0 尺寸也不能落到非法值")

        // 任意像素请求都只会落到 3 个 tier 上，缓存键空间因此有界。
        for requested in stride(from: 0, through: 4_096, by: 37) {
            let tier = ArtworkPixelTier.normalize(requested)
            XCTAssertTrue(tier.pixels >= requested || tier == .large, "requested=\(requested)")
        }
    }

    // MARK: 3. 无封面缓存：硬上限 + TTL

    func testMissingCacheHonorsHardLimitTTLAndClear() {
        let base = Date(timeIntervalSince1970: 0)

        // TTL：过期条目立刻失效并被移除。
        var ttlCache = ArtworkMissingCache(limit: 10, ttl: 120)
        ttlCache.markMissing("a", now: base)
        XCTAssertTrue(ttlCache.contains("a", now: base.addingTimeInterval(119)))
        XCTAssertFalse(ttlCache.contains("a", now: base.addingTimeInterval(120)), "到 TTL 即失效")
        XCTAssertEqual(ttlCache.count, 0, "失效条目应当被顺手清掉")

        // 小上限：只保留最新的 limit 条。
        var smallCache = ArtworkMissingCache(limit: 3, ttl: 3_600)
        for index in 0..<5 {
            smallCache.markMissing("key-\(index)", now: base.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(smallCache.count, 3)
        XCTAssertTrue(smallCache.contains("key-4", now: base.addingTimeInterval(5)))
        XCTAssertTrue(smallCache.contains("key-2", now: base.addingTimeInterval(5)))
        XCTAssertFalse(smallCache.contains("key-1", now: base.addingTimeInterval(5)))
        XCTAssertFalse(smallCache.contains("key-0", now: base.addingTimeInterval(5)))

        smallCache.clear("key-4")
        XCTAssertEqual(smallCache.count, 2)
        XCTAssertFalse(smallCache.contains("key-4", now: base.addingTimeInterval(5)))

        // limit 至少为 1，且 512 是硬上限。
        XCTAssertEqual(ArtworkMissingCache(limit: 0, ttl: 1).limit, 1)

        var capped = ArtworkMissingCache(limit: 512, ttl: 3_600)
        for index in 0..<600 {
            capped.markMissing("key-\(index)", now: base.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(capped.count, 512, "超过 512 条必须被裁剪")
        XCTAssertTrue(capped.contains("key-599", now: base.addingTimeInterval(600)))
        XCTAssertTrue(capped.contains("key-88", now: base.addingTimeInterval(600)))
        XCTAssertFalse(capped.contains("key-87", now: base.addingTimeInterval(600)))
        XCTAssertFalse(capped.contains("key-0", now: base.addingTimeInterval(600)))
    }
}
