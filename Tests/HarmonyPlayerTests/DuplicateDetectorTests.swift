import XCTest

@testable import HarmonyPlayer

/// `DuplicateDetector` 的行为契约。
final class DuplicateDetectorTests: XCTestCase {

    // MARK: - normalizeTitle

    func testNormalizeTitleKeepsPlainTitle() {
        XCTAssertEqual(DuplicateDetector.normalizeTitle("海阔天空"), "海阔天空")
        XCTAssertEqual(DuplicateDetector.normalizeTitle("晴天"), "晴天")
    }

    func testNormalizeTitleStripsTrailingDigitsAndSpaces() {
        XCTAssertEqual(DuplicateDetector.normalizeTitle("海阔天空 2"), "海阔天空")
        XCTAssertEqual(DuplicateDetector.normalizeTitle("海阔天空2"), "海阔天空")
        XCTAssertEqual(DuplicateDetector.normalizeTitle("海阔天空 12"), "海阔天空")
        XCTAssertEqual(DuplicateDetector.normalizeTitle("海阔天空  3 "), "海阔天空")
    }

    func testNormalizeTitleKeepsNonDigitSuffix() {
        // 非数字尾缀（"Live" 不属于归一化范围）保持原样。
        XCTAssertEqual(DuplicateDetector.normalizeTitle("海阔天空 (Live)"), "海阔天空 (Live)")
        XCTAssertEqual(DuplicateDetector.normalizeTitle("海阔天空 Live"), "海阔天空 Live")
    }

    // MARK: - detectGroups 基本判定

    func testDetectGroupsGroupsByNormalizedTitleAndFields() {
        // 用户原话场景：海阔天空 与 海阔天空 2，歌手/专辑/时长全一致 → 一组
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(Set(groups[0].map(\.id)), Set([testUUID(1), testUUID(2)]))
    }

    func testDetectGroupsDoesNotGroupWhenArtistDiffers() {
        // 标题归一化后相同，但歌手不同 → 不应判为重复
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "周杰伦", album: "海阔天空", duration: 326)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertTrue(groups.isEmpty)
    }

    func testDetectGroupsDoesNotGroupWhenAlbumDiffers() {
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "Beyond", album: "乐与怒", duration: 326)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertTrue(groups.isEmpty)
    }

    func testDetectGroupsToleratesDurationWithin2Seconds() {
        // 时长容差 ±2 秒：326 vs 327.5 视为同时长
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "Beyond", album: "海阔天空", duration: 327.5)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertEqual(groups.count, 1)
    }

    func testDetectGroupsSplitsWhenDurationDiffersBeyondTolerance() {
        // 同名同字段但时长差超过 2 秒：326 vs 330 视为两首歌
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "Beyond", album: "海阔天空", duration: 330)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - 多组与排序

    func testDetectGroupsReturnsMultipleGroups() {
        // 两组重复：海阔天空×2 与 晴天×2
        let a1 = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326,
                               dateAdded: Date(timeIntervalSince1970: 1_000))
        let a2 = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "Beyond", album: "海阔天空", duration: 326,
                               dateAdded: Date(timeIntervalSince1970: 1_100))
        let b1 = makeTestTrack(id: testUUID(3), title: "晴天",
                               artist: "周杰伦", album: "叶惠美", duration: 240,
                               dateAdded: Date(timeIntervalSince1970: 1_200))
        let b2 = makeTestTrack(id: testUUID(4), title: "晴天 2",
                               artist: "周杰伦", album: "叶惠美", duration: 240,
                               dateAdded: Date(timeIntervalSince1970: 1_300))
        let groups = DuplicateDetector.detectGroups(in: [a1, a2, b1, b2])
        XCTAssertEqual(groups.count, 2)
        // 组间顺序：组首 dateAdded 降序，晴天组(1300) 在海阔天空组(1100) 之前
        XCTAssertEqual(groups[0].first?.title, "晴天 2")
        XCTAssertEqual(groups[1].first?.title, "海阔天空 2")
        // 组内：dateAdded 降序
        XCTAssertEqual(groups[0].map(\.id), [testUUID(4), testUUID(3)])
        XCTAssertEqual(groups[1].map(\.id), [testUUID(2), testUUID(1)])
    }

    func testDetectGroupsIgnoresSingleOccurrenceTracks() {
        // 单首歌不构成重复组
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "完全不同",
                               artist: "其他人", album: "其他专辑", duration: 200)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertTrue(groups.isEmpty)
    }

    func testDetectGroupsSplitsBucketByDurationCluster() {
        // 同名同字段，但时长成两簇：326/327 一簇，340/341 另一簇
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326,
                               dateAdded: Date(timeIntervalSince1970: 1_000))
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "Beyond", album: "海阔天空", duration: 327,
                               dateAdded: Date(timeIntervalSince1970: 1_100))
        let c = makeTestTrack(id: testUUID(3), title: "海阔天空 3",
                               artist: "Beyond", album: "海阔天空", duration: 340,
                               dateAdded: Date(timeIntervalSince1970: 1_200))
        let d = makeTestTrack(id: testUUID(4), title: "海阔天空 4",
                               artist: "Beyond", album: "海阔天空", duration: 341,
                               dateAdded: Date(timeIntervalSince1970: 1_300))
        let groups = DuplicateDetector.detectGroups(in: [a, b, c, d])
        XCTAssertEqual(groups.count, 2)
        // 第一簇是 340/341（最新），第二簇是 326/327
        XCTAssertEqual(groups[0].map(\.id), [testUUID(4), testUUID(3)])
        XCTAssertEqual(groups[1].map(\.id), [testUUID(2), testUUID(1)])
    }

    // MARK: - 大小写与空白

    func testDetectGroupsIsCaseInsensitiveForArtistAndAlbum() {
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "BEYOND", album: "海阔天空", duration: 326)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertEqual(groups.count, 1)
    }

    func testDetectGroupsTrimsWhitespaceInArtistAndAlbum() {
        let a = makeTestTrack(id: testUUID(1), title: "海阔天空",
                               artist: "Beyond", album: "海阔天空", duration: 326)
        let b = makeTestTrack(id: testUUID(2), title: "海阔天空 2",
                               artist: "  Beyond  ", album: " 海阔天空 ", duration: 326)
        let groups = DuplicateDetector.detectGroups(in: [a, b])
        XCTAssertEqual(groups.count, 1)
    }
}
