import XCTest

@testable import HarmonyPlayer

/// `LibraryBrowseSnapshot.build` 的行为契约。
/// 所有排序断言都用 ASCII 标题，避免依赖运行环境的 CJK 排序规则；
/// 中文只用于“相等/包含”这类与排序无关的断言。
final class LibraryBrowseSnapshotTests: XCTestCase {

    // MARK: 1. 标题自然排序 + 升降序 + 平局稳定

    func testTitleNaturalSortIsNumericAwareAndTiesStayStable() {
        let trackOne = makeTestTrack(id: testUUID(1), title: "Track 1")
        let trackTwo = makeTestTrack(id: testUUID(2), title: "Track 2")
        let trackTen = makeTestTrack(id: testUUID(3), title: "Track 10")
        let tieLow = makeTestTrack(id: testUUID(4), title: "Same Title")
        let tieHigh = makeTestTrack(id: testUUID(5), title: "Same Title")
        // 同一输入被两次打乱顺序，用来证明平局不依赖输入顺序。
        let tracks = [trackTen, tieHigh, trackOne, tieLow, trackTwo]
        let shuffled = [tieLow, trackTwo, trackTen, tieHigh, trackOne]

        let ascending = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .all, sortOrder: .title, ascending: true),
            tracks: tracks,
            favoriteIDs: [],
            recentTracks: []
        )
        // 自然排序：1 < 2 < 10，而不是字典序的 1 < 10 < 2。
        XCTAssertEqual(
            ascending.tracks.filter { $0.title.hasPrefix("Track") }.map(\.title),
            ["Track 1", "Track 2", "Track 10"]
        )
        XCTAssertEqual(
            ascending.tracks.filter { $0.title == "Same Title" }.map(\.id),
            [testUUID(4), testUUID(5)],
            "平局按 id 升序，与输入顺序无关"
        )

        let ascendingShuffled = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .all, sortOrder: .title, ascending: true),
            tracks: shuffled,
            favoriteIDs: [],
            recentTracks: []
        )
        XCTAssertEqual(
            ascendingShuffled.tracks.map(\.id),
            ascending.tracks.map(\.id),
            "打乱输入后结果完全一致"
        )

        let descending = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .all, sortOrder: .title, ascending: false),
            tracks: tracks,
            favoriteIDs: [],
            recentTracks: []
        )
        XCTAssertEqual(
            descending.tracks.filter { $0.title.hasPrefix("Track") }.map(\.title),
            ["Track 10", "Track 2", "Track 1"]
        )
        XCTAssertEqual(
            descending.tracks.filter { $0.title == "Same Title" }.map(\.id),
            [testUUID(4), testUUID(5)],
            "平局兜底始终是 id 升序，不被 descending 反转"
        )

        // 中文同名曲同样只依赖 id 兜底，与 CJK 排序规则无关。
        let chineseA = makeTestTrack(id: testUUID(6), title: "晴天")
        let chineseB = makeTestTrack(id: testUUID(7), title: "晴天")
        let chinese = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .all, sortOrder: .title, ascending: false),
            tracks: [chineseB, chineseA],
            favoriteIDs: [],
            recentTracks: []
        )
        XCTAssertEqual(chinese.tracks.map(\.id), [testUUID(6), testUUID(7)])
    }

    func testEqualDurationFallsBackToTitleThenID() {
        let alpha = makeTestTrack(id: testUUID(11), title: "Alpha", duration: 200)
        let bravo = makeTestTrack(id: testUUID(12), title: "Bravo", duration: 200)
        let charlie = makeTestTrack(id: testUUID(13), title: "Charlie", duration: 100)

        let snapshot = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .all, sortOrder: .duration, ascending: true),
            tracks: [bravo, alpha, charlie],
            favoriteIDs: [],
            recentTracks: []
        )
        XCTAssertEqual(snapshot.tracks.map(\.title), ["Charlie", "Alpha", "Bravo"])
    }

    // MARK: 2. 搜索：中文、空白裁剪、大小写、字段覆盖

    func testSearchTrimsWhitespaceIsCaseInsensitiveAndCoversAllDisplayFields() {
        let chinese = makeTestTrack(
            id: testUUID(21),
            title: "晴天",
            artist: "周杰伦",
            album: "叶惠美"
        )
        let latin = makeTestTrack(
            id: testUUID(22),
            title: "Hello World",
            artist: "The Beatles",
            album: "Abbey Road"
        )
        // title/artist/album 都为空，用来验证 display* 兜底值也参与搜索。
        let blank = makeTestTrack(id: testUUID(23), title: "", artist: "   ", album: "")
        let tracks = [chinese, latin, blank]

        func search(_ query: String) -> [UUID] {
            LibraryBrowseSnapshot.build(
                request: makeBrowseRequest(section: .all, search: query),
                tracks: tracks,
                favoriteIDs: [],
                recentTracks: []
            ).tracks.map(\.id)
        }

        XCTAssertEqual(search("  晴天  "), [testUUID(21)], "首尾空白被裁剪后仍命中标题")
        XCTAssertEqual(search("周杰伦"), [testUUID(21)], "命中艺人")
        XCTAssertEqual(search("叶惠美"), [testUUID(21)], "命中专辑")
        XCTAssertEqual(search("BEATLES"), [testUUID(22)], "大小写不敏感")
        XCTAssertEqual(search("hello world"), [testUUID(22)], "标题小写查询命中大写标题")
        XCTAssertEqual(search("未知艺人"), [testUUID(23)], "空白艺人走 displayArtist 兜底值")
        XCTAssertEqual(search("   "), [testUUID(21), testUUID(22), testUUID(23)], "纯空白查询等价于不筛选")
        XCTAssertTrue(search("不存在的关键词").isEmpty)
    }

    // MARK: 3. favorites / history 过滤

    func testFavoritesAndHistorySectionsFilterAndReSort() {
        let alpha = makeTestTrack(id: testUUID(31), title: "Alpha")
        let bravo = makeTestTrack(id: testUUID(32), title: "Bravo")
        let charlie = makeTestTrack(id: testUUID(33), title: "Charlie")
        let delta = makeTestTrack(id: testUUID(34), title: "Delta")
        let tracks = [alpha, bravo, charlie, delta]
        let favorites: Set<UUID> = [testUUID(31), testUUID(33)]
        // 传入顺序刻意与标题顺序相反。
        let recent = [delta, bravo]

        let favoriteSnapshot = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .favorites),
            tracks: tracks,
            favoriteIDs: favorites,
            recentTracks: recent
        )
        XCTAssertEqual(favoriteSnapshot.tracks.map(\.id), [testUUID(31), testUUID(33)])
        XCTAssertTrue(favoriteSnapshot.albums.isEmpty)
        XCTAssertTrue(favoriteSnapshot.artists.isEmpty)
        XCTAssertTrue(favoriteSnapshot.folders.isEmpty)

        let historySnapshot = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .history),
            tracks: tracks,
            favoriteIDs: favorites,
            recentTracks: recent
        )
        XCTAssertEqual(
            historySnapshot.tracks.map(\.id),
            [testUUID(32), testUUID(34)],
            "history 只看 recentTracks，并按请求的排序重新排"
        )
        XCTAssertTrue(historySnapshot.favorites.isEmpty, "history 分支不计算 favorites")
    }

    // MARK: 4. 同名专辑 + 不同艺人

    func testAlbumsGroupSameTitleFromDifferentArtistsSeparately() {
        let first = makeTestTrack(
            id: testUUID(41), title: "First", artist: "Zed", album: "Shared", directory: "/music/zed"
        )
        let second = makeTestTrack(
            id: testUUID(42), title: "Second", artist: "Zed", album: "Shared", directory: "/music/zed"
        )
        let third = makeTestTrack(
            id: testUUID(43), title: "Third", artist: "Amy", album: "Shared", directory: "/music/amy"
        )
        let fourth = makeTestTrack(
            id: testUUID(44), title: "Fourth", artist: "Zed", album: "Album A", directory: "/music/zed"
        )

        let snapshot = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .albums),
            tracks: [third, first, fourth, second],
            favoriteIDs: [],
            recentTracks: []
        )

        XCTAssertEqual(snapshot.albums.count, 3, "同名不同艺人应拆成两张专辑")
        XCTAssertEqual(snapshot.albums.map(\.title), ["Album A", "Shared", "Shared"])
        XCTAssertEqual(
            snapshot.albums.map(\.artist),
            ["Zed", "Amy", "Zed"],
            "专辑同名时按艺人升序决定先后"
        )
        XCTAssertEqual(snapshot.albums[1].tracks.map(\.title), ["Third"])
        XCTAssertEqual(snapshot.albums[2].tracks.map(\.title), ["First", "Second"])
        XCTAssertEqual(snapshot.tracks.map(\.title), ["First", "Fourth", "Second", "Third"])
    }

    // MARK: 5. artists / folders 分组 + 强制标题升序

    func testArtistsAndFoldersGroupAndForceTitleOrder() throws {
        // duration 刻意与标题顺序相反，用来证明 albums/artists/folders 忽略请求的排序。
        let zeta = makeTestTrack(
            id: testUUID(51), title: "Zeta", artist: "Zed", album: "B",
            duration: 500, directory: "/root/AlbumB", fileName: "z.mp3"
        )
        let alpha = makeTestTrack(
            id: testUUID(52), title: "Alpha", artist: "Amy", album: "A",
            duration: 10, directory: "/root/AlbumA", fileName: "a.mp3"
        )
        let beta = makeTestTrack(
            id: testUUID(53), title: "Beta", artist: "Amy", album: "A",
            duration: 300, directory: "/root/AlbumA", fileName: "b.mp3"
        )
        let tracks = [zeta, alpha, beta]
        let descendingByDuration = makeBrowseRequest(
            section: .folders, sortOrder: .duration, ascending: false
        )

        let folders = LibraryBrowseSnapshot.build(
            request: descendingByDuration, tracks: tracks, favoriteIDs: [], recentTracks: []
        )
        XCTAssertEqual(folders.folders.map(\.name), ["AlbumA", "AlbumB"], "文件夹按名称升序")
        XCTAssertEqual(folders.folders.first?.tracks.map(\.title), ["Alpha", "Beta"], "目录内按标题升序")
        let albumAPath = try XCTUnwrap(folders.folders.first?.path)
        XCTAssertTrue(albumAPath.hasSuffix("AlbumA"), "分组键应是父目录，实际：\(albumAPath)")
        XCTAssertFalse(albumAPath.contains("a.mp3"), "分组键不应包含文件名")
        XCTAssertEqual(
            folders.tracks.map(\.title),
            ["Alpha", "Beta", "Zeta"],
            "folders 强制标题升序，忽略 duration/descending"
        )

        let artists = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .artists, sortOrder: .duration, ascending: false),
            tracks: tracks,
            favoriteIDs: [],
            recentTracks: []
        )
        XCTAssertEqual(artists.artists.map(\.name), ["Amy", "Zed"])
        XCTAssertEqual(artists.artists.first?.tracks.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(artists.artists.first?.albumCount, 1)

        let albums = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .albums, sortOrder: .duration, ascending: false),
            tracks: tracks,
            favoriteIDs: [],
            recentTracks: []
        )
        XCTAssertEqual(albums.albums.map(\.title), ["A", "B"])
        XCTAssertEqual(albums.albums.map(\.artist), ["Amy", "Zed"])
    }

    // MARK: 6. 首页：最近专辑 / 收藏 / 最近播放上限

    func testHomeSectionGroupsNewestAlbumsFirstAndCapsRecentTracks() {
        let beta1 = makeTestTrack(
            id: testUUID(61), title: "Beta 1", artist: "B", album: "Beta",
            dateAdded: Date(timeIntervalSince1970: 500)
        )
        let alpha1 = makeTestTrack(
            id: testUUID(62), title: "Alpha 1", artist: "A", album: "Alpha",
            dateAdded: Date(timeIntervalSince1970: 300)
        )
        let alpha2 = makeTestTrack(
            id: testUUID(63), title: "Alpha 2", artist: "A", album: "Alpha",
            dateAdded: Date(timeIntervalSince1970: 200)
        )
        let gamma1 = makeTestTrack(
            id: testUUID(64), title: "Gamma 1", artist: "A", album: "Gamma",
            dateAdded: Date(timeIntervalSince1970: 100)
        )
        // 与 store 的约定一致：tracks 已经按 dateAdded 降序。
        let tracks = [beta1, alpha1, alpha2, gamma1]
        let recent = (0..<25).map { index in
            makeTestTrack(id: testUUID(100 + index), title: "Recent \(index)")
        }
        let favorites: Set<UUID> = [testUUID(63), testUUID(61)]

        let snapshot = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .home, search: ""),
            tracks: tracks,
            favoriteIDs: favorites,
            recentTracks: recent
        )

        XCTAssertEqual(snapshot.tracks.map(\.id), tracks.map(\.id), "首页保持 store 的原始顺序")
        XCTAssertEqual(snapshot.favorites.map(\.id), [testUUID(61), testUUID(63)], "收藏保持输入顺序")
        XCTAssertEqual(snapshot.recentTracks.count, 20, "最近播放截断到 20 首")
        XCTAssertEqual(snapshot.recentTracks.map(\.id), recent.prefix(20).map(\.id))
        XCTAssertEqual(snapshot.homeAlbums.map(\.title), ["Beta", "Alpha", "Gamma"], "按专辑内最新歌曲倒序")
        XCTAssertEqual(snapshot.homeAlbums.first?.tracks.count, 1)
        XCTAssertEqual(snapshot.homeAlbums[1].tracks.map(\.id), [testUUID(62), testUUID(63)])
        XCTAssertTrue(snapshot.albums.isEmpty, "首页不填充 albums/artists/folders")

        // 首页 + 非空搜索会退化为扁平搜索。
        let searched = LibraryBrowseSnapshot.build(
            request: makeBrowseRequest(section: .home, search: "Alpha"),
            tracks: tracks,
            favoriteIDs: favorites,
            recentTracks: recent
        )
        XCTAssertEqual(searched.tracks.map(\.id), [testUUID(62), testUUID(63)])
        XCTAssertTrue(searched.homeAlbums.isEmpty)
        XCTAssertTrue(searched.favorites.isEmpty)
        XCTAssertTrue(searched.recentTracks.isEmpty)
    }
}
