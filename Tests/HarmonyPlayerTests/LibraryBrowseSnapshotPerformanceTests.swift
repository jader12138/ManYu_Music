import XCTest

@testable import HarmonyPlayer

/// 10,000 首规模的内存基准。
///
/// 只用测试内构造的假数据，不扫描磁盘、不读取真实用户音乐，也不做任何解码。
/// 全部断言只保证“结果正确、规模真实”，不设任何耗时阈值；
/// 输出的是本机实际测量值，不代表 FPS、启动耗时或任何用户可见指标。
final class LibraryBrowseSnapshotPerformanceTests: XCTestCase {

    private static let librarySize = 10_000

    /// 索引 + 排序：走 XCTest 的 `measure`，只报告，不断言阈值。
    func testBuildPerformanceOnTenThousandTracks() {
        let tracks = makeSyntheticTracks(count: Self.librarySize)
        let request = makeBrowseRequest(section: .all, search: "", sortOrder: .title, ascending: true)

        // 先跑一次并断言正确性，避免把断言开销算进测量区间。
        let probe = LibraryBrowseSnapshot.build(
            request: request, tracks: tracks, favoriteIDs: [], recentTracks: []
        )
        XCTAssertEqual(probe.tracks.count, Self.librarySize)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(options: options) {
            _ = LibraryBrowseSnapshot.build(
                request: request, tracks: tracks, favoriteIDs: [], recentTracks: []
            )
        }
    }

    /// 搜索 + 排序：用 ContinuousClock 分别测量新实现与旧实现参考，并验证结果一致。
    ///
    /// 公平性约定：
    /// - 同一份 10,000 首输入、同一查询、同一排序方向；
    /// - 两边都先各跑一次预热，避免把首次调用的惰性初始化算进对比；
    /// - 旧实现参考复现的是优化前的写法：在过滤与比较器内部反复计算
    ///   `displayTitle/displayArtist/displayAlbum`（含 trim），
    ///   新实现则在构建 `SearchRow` 时对每首歌只算一次。
    /// - 只比较“顺序结果是否相同”，不设耗时阈值，也不换算成任何倍数结论。
    func testSearchTimingComparedWithLegacyReference() throws {
        let tracks = makeSyntheticTracks(count: Self.librarySize)
        let query = "曲目 42"
        let request = makeBrowseRequest(section: .all, search: query, sortOrder: .title, ascending: true)
        let clock = ContinuousClock()

        _ = LibraryBrowseSnapshot.build(
            request: request, tracks: tracks, favoriteIDs: [], recentTracks: []
        )
        _ = legacyReferenceSearchAndSort(tracks, query: query, ascending: true)

        let optimizedStart = clock.now
        let optimized = LibraryBrowseSnapshot.build(
            request: request, tracks: tracks, favoriteIDs: [], recentTracks: []
        )
        let optimizedElapsed = optimizedStart.duration(to: clock.now)

        let legacyStart = clock.now
        let legacy = legacyReferenceSearchAndSort(tracks, query: query, ascending: true)
        let legacyElapsed = legacyStart.duration(to: clock.now)

        XCTAssertGreaterThan(optimized.tracks.count, 0, "基准查询应有命中")
        XCTAssertEqual(optimized.tracks.count, legacy.count)
        XCTAssertEqual(
            optimized.tracks.map(\.id),
            legacy.map(\.id),
            "新旧实现的排序结果必须完全一致"
        )

        let report = """
        10,000 首内存基准（无磁盘、无解码、无阈值断言）
        - LibraryBrowseSnapshot.build(.all, 搜索 "\(query)", 标题升序)：\(Self.milliseconds(optimizedElapsed)) ms，命中 \(optimized.tracks.count) 首
        - 旧实现参考（比较器/过滤器内重复 display* 与 trim）：\(Self.milliseconds(legacyElapsed)) ms，命中 \(legacy.count) 首
        说明：以上仅为本机实际测量值，用于观察本轮优化的相对开销，不代表 FPS、启动耗时或任何用户可见性能指标。
        """
        print(report)
        add(XCTAttachment(string: report))
    }

    // MARK: - 基准数据

    /// 10,000 首确定性假数据：不触碰文件系统，只用字符串与数值构造。
    private func makeSyntheticTracks(count: Int) -> [Track] {
        (0..<count).map { index in
            Track(
                id: testUUID(index + 1),
                url: URL(fileURLWithPath: "/synthetic/library/folder-\(index % 40)/track-\(index).mp3"),
                title: "曲目 \(index % 500)",
                artist: "艺人 \(index % 120)",
                album: "专辑 \(index % 200)",
                duration: Double(60 + (index % 240)),
                dateAdded: Date(timeIntervalSince1970: 1_700_000_000 - Double(index))
            )
        }
    }

    /// 优化前的等价写法：过滤与比较都在闭包里重复计算 display* 字段。
    private func legacyReferenceSearchAndSort(
        _ tracks: [Track],
        query: String,
        ascending: Bool
    ) -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty ? tracks : tracks.filter { track in
            track.displayTitle.localizedStandardContains(trimmed)
                || track.displayArtist.localizedStandardContains(trimmed)
                || track.displayAlbum.localizedStandardContains(trimmed)
        }
        return filtered.sorted { lhs, rhs in
            let comparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            if comparison == .orderedSame {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
