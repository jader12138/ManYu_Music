import Combine
import Foundation
import XCTest

@testable import HarmonyPlayer

/// 进度 tick 的失效范围：只应该让 `PlaybackClock` 的观察者重绘。
///
/// 这里刻意 **不创建 `AudioPlayer`**：它的 `init` 会读写真实的
/// `UserDefaults.standard`（音量 / 播放记忆）、注册全局按键监听与
/// `MPRemoteCommandCenter`，属于用户级副作用。当前 API 不支持注入临时
/// UserDefaults suite，所以对播放器一侧改用源码结构断言，不碰用户默认值。
@MainActor
final class PlaybackClockIsolationTests: XCTestCase {

    func testClockTicksStayOffAudioPlayerObjectWillChange() throws {
        let clock = PlaybackClock()

        var clockEmissions = 0
        let token = clock.objectWillChange.sink { clockEmissions += 1 }

        // 100 次 0.25s 进度 tick，等价于 25 秒播放。
        for tick in 1...100 {
            clock.currentTime = Double(tick) * 0.25
        }

        XCTAssertEqual(clockEmissions, 100, "每次进度 tick 恰好触发一次 clock.objectWillChange")
        XCTAssertEqual(clock.currentTime, 25, accuracy: 0.0001)
        XCTAssertNil(clock.sleepTimerRemaining)

        // clock 只持有进度状态：不引用播放器，也就没有任何路径能把 tick 变成播放器的变更。
        for child in Mirror(reflecting: clock).children {
            XCTAssertFalse(child.value is AudioPlayer, "PlaybackClock 不应持有 AudioPlayer")
        }

        withExtendedLifetime(token) {}

        // 源码结构断言：一旦有人把 clock 接回 AudioPlayer（转发或订阅），这里就会失败。
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/HarmonyPlayerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appendingPathComponent("Sources/HarmonyPlayer/Services/AudioPlayer.swift")
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw XCTSkip("找不到 AudioPlayer.swift，跳过源码结构断言")
        }

        // 去掉行注释，避免文档注释里的说明文字被当成代码命中。
        // 该文件内没有字符串包含 "//"，所以这种裁剪是安全的。
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let range = line.range(of: "//") else { return line }
                return line[line.startIndex..<range.lowerBound]
            }
            .joined(separator: "\n")

        XCTAssertTrue(code.contains("let clock = PlaybackClock()"), "clock 应是独立存储属性")
        XCTAssertFalse(code.contains("clock.objectWillChange"), "clock 的变更不应转发进 AudioPlayer")
        XCTAssertFalse(code.contains("clock.$"), "AudioPlayer 不应订阅 clock 的 @Published 投影")
        XCTAssertFalse(code.contains("objectWillChange.send"), "AudioPlayer 不应手工转发 clock 变更")
    }
}
