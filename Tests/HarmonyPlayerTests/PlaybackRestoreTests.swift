import Foundation
import XCTest

@testable import HarmonyPlayer

/// 重启后播放状态恢复：库从磁盘异步加载，启动瞬间 tracks 为空，
/// 加载完成后必须能用存档重建当前曲目、队列与进度。
@MainActor
final class PlaybackRestoreTests: XCTestCase {

    private static let trackIDKey = "ManyuMusic.playback.trackID"
    private static let queueIDsKey = "ManyuMusic.playback.queueIDs"
    private static let currentIndexKey = "ManyuMusic.playback.currentIndex"
    private static let currentTimeKey = "ManyuMusic.playback.currentTime"
    private static let modeKey = "ManyuMusic.playback.mode"

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HarmonyPlayerTests.playback-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// 构造指向真实空文件的曲目（恢复逻辑要做 fileExists 校验）。
    private func makeTracks(in workspace: TempWorkspace) throws -> [Track] {
        let titles = ["alpha", "beta", "gamma"]
        return try titles.enumerated().map { index, title in
            let fileName = "\(title).mp3"
            try workspace.write(Data(), to: fileName)
            return makeTestTrack(
                id: testUUID(index + 1),
                title: title,
                duration: 200,
                directory: workspace.root.path,
                fileName: fileName
            )
        }
    }

    func testEmptyTracksDoesNotConsumeRestoreAttempt() throws {
        let workspace = makeTempWorkspace()
        let tracks = try makeTracks(in: workspace)
        let target = tracks[1]

        defaults.set(target.id.uuidString, forKey: Self.trackIDKey)
        defaults.set(tracks.map { $0.id.uuidString }, forKey: Self.queueIDsKey)
        defaults.set(1, forKey: Self.currentIndexKey)
        defaults.set(42.0, forKey: Self.currentTimeKey)

        let player = AudioPlayer(defaults: defaults)

        // 模拟 onAppear 时库仍在加载：第一次给空数组，必须安静返回且不"烧掉"恢复机会。
        player.restorePlaybackState(from: [])
        XCTAssertNil(player.currentTrack, "库未加载完不应恢复出曲目")

        // 模拟 isLoading 变 false 后再次调用：此时必须真正恢复。
        player.restorePlaybackState(from: tracks)

        XCTAssertEqual(player.currentTrack?.id, target.id, "应恢复到上次播放的曲目")
        XCTAssertEqual(player.queue.map(\.id), tracks.map(\.id), "应按存档顺序重建整个队列")
        XCTAssertEqual(player.currentIndex, 1, "应恢复队列中的位置")
        XCTAssertEqual(player.currentTime, 42.0, accuracy: 0.01, "应恢复播放进度")
        XCTAssertFalse(player.isPlaying, "恢复状态不应自动开始播放")
    }

    func testRestoreWithoutSavedQueueFallsBackToSingleTrack() throws {
        let workspace = makeTempWorkspace()
        let tracks = try makeTracks(in: workspace)
        let target = tracks[2]

        defaults.set(target.id.uuidString, forKey: Self.trackIDKey)
        // 故意不写 queueIDs：老版本/异常存档下应退化为单曲队列。
        defaults.set(90.0, forKey: Self.currentTimeKey)

        let player = AudioPlayer(defaults: defaults)
        player.restorePlaybackState(from: tracks)

        XCTAssertEqual(player.currentTrack?.id, target.id)
        XCTAssertEqual(player.queue.map(\.id), [target.id], "无队列存档时退化为仅含当前曲目的队列")
        XCTAssertEqual(player.currentIndex, 0)
    }

    func testRestoreWithoutSavedStateLeavesPlayerEmpty() throws {
        let workspace = makeTempWorkspace()
        let tracks = try makeTracks(in: workspace)

        let player = AudioPlayer(defaults: defaults)
        player.restorePlaybackState(from: tracks)

        XCTAssertNil(player.currentTrack, "从无播放存档时不应恢复任何曲目")
        XCTAssertTrue(player.queue.isEmpty)
    }
}
