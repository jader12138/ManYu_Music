import Foundation
import XCTest

@testable import HarmonyPlayer

/// 三态合一播放模式：顺序播放 → 单曲循环 → 随机播放，点击循环切换；
/// 切换时底层 isShuffle / repeatMode 必须同步成对应的执行状态。
@MainActor
final class PlaybackModeTests: XCTestCase {

    func testPlaybackModeCyclesInOrder() {
        let player = AudioPlayer()

        XCTAssertEqual(player.playbackMode, .sequential)
        XCTAssertFalse(player.isShuffle)
        XCTAssertEqual(player.repeatMode, .off)

        player.cyclePlaybackMode()
        XCTAssertEqual(player.playbackMode, .singleRepeat)
        XCTAssertEqual(player.repeatMode, .one)
        XCTAssertFalse(player.isShuffle)

        player.cyclePlaybackMode()
        XCTAssertEqual(player.playbackMode, .shuffle)
        XCTAssertTrue(player.isShuffle)
        XCTAssertEqual(player.repeatMode, .off)

        player.cyclePlaybackMode()
        XCTAssertEqual(player.playbackMode, .sequential)
        XCTAssertFalse(player.isShuffle)
        XCTAssertEqual(player.repeatMode, .off)
    }

    func testSetPlaybackModeDirectly() {
        let player = AudioPlayer()

        player.setPlaybackMode(.shuffle)
        XCTAssertEqual(player.playbackMode, .shuffle)
        XCTAssertTrue(player.isShuffle)
        XCTAssertEqual(player.repeatMode, .off)

        player.setPlaybackMode(.singleRepeat)
        XCTAssertEqual(player.playbackMode, .singleRepeat)
        XCTAssertFalse(player.isShuffle)
        XCTAssertEqual(player.repeatMode, .one)

        player.setPlaybackMode(.sequential)
        XCTAssertEqual(player.playbackMode, .sequential)
        XCTAssertFalse(player.isShuffle)
        XCTAssertEqual(player.repeatMode, .off)
    }

    func testPlaybackModeNextOrder() {
        XCTAssertEqual(PlaybackMode.sequential.next, .singleRepeat)
        XCTAssertEqual(PlaybackMode.singleRepeat.next, .shuffle)
        XCTAssertEqual(PlaybackMode.shuffle.next, .sequential)
    }
}
