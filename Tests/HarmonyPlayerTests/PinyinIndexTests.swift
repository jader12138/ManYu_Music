import XCTest
@testable import HarmonyPlayer

/// 拼音搜索索引：全拼 / 首字母键生成与匹配规则。
final class PinyinIndexTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PinyinIndex.clearCacheForTesting()
    }

    func testChineseFullPinyin() {
        let keys = PinyinIndex.keys(for: "周杰伦")
        XCTAssertEqual(keys.full, "zhoujielun")
        XCTAssertEqual(keys.initials, "zjl")
    }

    func testChineseInitialQueryMatches() {
        let keys = PinyinIndex.keys(for: "晴天")
        XCTAssertEqual(keys.initials, "qt")
        XCTAssertTrue(keys.matches("qt"))
        XCTAssertTrue(keys.matches("qingt"))
        XCTAssertTrue(keys.matches("qing"))
        XCTAssertFalse(keys.matches("xqt"))
    }

    func testEnglishWordsKeepOriginalSpelling() {
        let keys = PinyinIndex.keys(for: "Jay Chou")
        XCTAssertEqual(keys.full, "jaychou")
        XCTAssertEqual(keys.initials, "jc")
        XCTAssertTrue(keys.matches("chou"))
        XCTAssertTrue(keys.matches("jc"))
    }

    func testMixedChineseAndEnglish() {
        let keys = PinyinIndex.keys(for: "夜曲")
        XCTAssertEqual(keys.full, "yequ")
        XCTAssertEqual(keys.initials, "yq")
    }

    func testNumbersAreKept() {
        let keys = PinyinIndex.keys(for: "夜曲2005")
        // 数字附着在前一音节 token 上：全拼保留数字，首字母取自字母部分。
        XCTAssertEqual(keys.full, "yequ2005")
        XCTAssertEqual(keys.initials, "yq")
        XCTAssertTrue(keys.matches("yequ2005"))
        XCTAssertTrue(keys.matches("2005"))
    }

    func testEmptyAndSymbolOnlyInput() {
        XCTAssertEqual(PinyinIndex.keys(for: ""), PinyinKeys(full: "", initials: ""))
        XCTAssertEqual(PinyinIndex.keys(for: "！？。"), PinyinKeys(full: "", initials: ""))
    }

    func testCacheReturnsConsistentResults() {
        let first = PinyinIndex.keys(for: "稻香")
        let second = PinyinIndex.keys(for: "稻香")
        XCTAssertEqual(first, second)
    }

    func testLibraryBrowseSnapshotMatchesByPinyin() {
        let track = Track(
            url: URL(fileURLWithPath: "/tmp/a.mp3"),
            title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269.3)

        let request = LibraryBrowseRequest(
            revision: 1, isLoading: false, section: .home,
            search: "zjl", sortOrder: .title, ascending: true)
        let snapshot = LibraryBrowseSnapshot.build(request: request, tracks: [track], favoriteIDs: [], recentTracks: [])
        XCTAssertEqual(snapshot.tracks.map(\.id), [track.id])

        let fullRequest = LibraryBrowseRequest(
            revision: 1, isLoading: false, section: .home,
            search: "zhoujielun", sortOrder: .title, ascending: true)
        let fullSnapshot = LibraryBrowseSnapshot.build(request: fullRequest, tracks: [track], favoriteIDs: [], recentTracks: [])
        XCTAssertEqual(fullSnapshot.tracks.map(\.id), [track.id])

        let missRequest = LibraryBrowseRequest(
            revision: 1, isLoading: false, section: .home,
            search: "wyt", sortOrder: .title, ascending: true)
        let missSnapshot = LibraryBrowseSnapshot.build(request: missRequest, tracks: [track], favoriteIDs: [], recentTracks: [])
        XCTAssertTrue(missSnapshot.tracks.isEmpty)
    }
}
