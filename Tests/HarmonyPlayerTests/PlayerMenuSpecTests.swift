import Foundation
import XCTest

@testable import HarmonyPlayer

/// Dock 右键菜单的纯数据规格：无曲目占位、播放态文案、禁用逻辑。
final class PlayerMenuSpecTests: XCTestCase {
    func testNoTrackShowsPlaceholderAndDisablesAllCommands() {
        let items = PlayerMenuSpec.items(title: nil, subtitle: nil, isPlaying: false)

        XCTAssertEqual(items.first, .headline(PlayerMenuSpec.noTrackPlaceholder))
        XCTAssertFalse(items.contains { item in
            if case .subline = item { return true } else { return false }
        })
        let commands = items.compactMap { item -> (PlayerMenuAction, Bool)? in
            guard case let .command(_, _, action, isEnabled) = item else { return nil }
            return (action, isEnabled)
        }
        XCTAssertEqual(commands.map(\.0), [.togglePlayback, .previous, .next])
        XCTAssertTrue(commands.allSatisfy { !$0.1 })
    }

    func testEmptyTitleTreatedAsNoTrack() {
        let items = PlayerMenuSpec.items(title: "", subtitle: "歌手", isPlaying: false)

        XCTAssertEqual(items.first, .headline(PlayerMenuSpec.noTrackPlaceholder))
    }

    func testPlayingTrackShowsPauseCommand() {
        let items = PlayerMenuSpec.items(title: "夜曲", subtitle: "周杰伦 · 十一月的萧邦", isPlaying: true)

        XCTAssertEqual(items.first, .headline("夜曲"))
        XCTAssertEqual(items[1], .subline("周杰伦 · 十一月的萧邦"))
        XCTAssertEqual(items[2], .separator)
        XCTAssertTrue(items.contains(
            .command(title: "暂停", symbol: "pause.fill", action: .togglePlayback, isEnabled: true)
        ))
        XCTAssertTrue(items.contains(.command(title: "上一首", symbol: "backward.fill", action: .previous, isEnabled: true)))
        XCTAssertTrue(items.contains(.command(title: "下一首", symbol: "forward.fill", action: .next, isEnabled: true)))
    }

    func testPausedTrackShowsPlayCommand() {
        let items = PlayerMenuSpec.items(title: "夜曲", subtitle: nil, isPlaying: false)

        XCTAssertTrue(items.contains(
            .command(title: "播放", symbol: "play.fill", action: .togglePlayback, isEnabled: true)
        ))
    }

    func testEmptySubtitleOmitsSubline() {
        let items = PlayerMenuSpec.items(title: "夜曲", subtitle: "", isPlaying: true)

        XCTAssertEqual(items[0], .headline("夜曲"))
        XCTAssertEqual(items[1], .separator)
    }
}
