import Foundation
import XCTest

@testable import HarmonyPlayer

/// 无缝播放（gapless）与淡入淡出（crossfade）设置项：
/// 默认值必须为关闭，存量偏好按 UserDefaults 读取；
/// 两个开关都关闭时 AudioPlayer 行为走历史 cut 链路（由其余测试覆盖）。
@MainActor
final class PlaybackTransitionSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HarmonyPlayerTests.transition-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsAreOff() {
        let player = AudioPlayer(defaults: defaults)
        XCTAssertFalse(player.gaplessEnabled, "gapless 默认必须关闭")
        XCTAssertFalse(player.crossfadeEnabled, "crossfade 默认必须关闭")
        XCTAssertEqual(player.crossfadeDuration, AudioPlayer.defaultCrossfadeDuration)
        XCTAssertEqual(player.crossfadeDuration, 6, "crossfade 默认时长 6 秒")
    }

    func testPersistedValuesAreReadBack() {
        defaults.set(true, forKey: AudioPlayer.gaplessPlaybackKey)
        defaults.set(true, forKey: AudioPlayer.crossfadeEnabledKey)
        defaults.set(9.0, forKey: AudioPlayer.crossfadeDurationKey)

        let player = AudioPlayer(defaults: defaults)
        XCTAssertTrue(player.gaplessEnabled)
        XCTAssertTrue(player.crossfadeEnabled)
        XCTAssertEqual(player.crossfadeDuration, 9)
    }

    func testOutOfRangeCrossfadeDurationIsClamped() {
        // 存了越界值（例如被外部写成 0 或 100）时钳制到滑块区间，不产生 0 秒淡变。
        defaults.set(0.0, forKey: AudioPlayer.crossfadeDurationKey)
        XCTAssertEqual(AudioPlayer(defaults: defaults).crossfadeDuration, 3)

        defaults.set(100.0, forKey: AudioPlayer.crossfadeDurationKey)
        XCTAssertEqual(AudioPlayer(defaults: defaults).crossfadeDuration, 12)
    }
}
