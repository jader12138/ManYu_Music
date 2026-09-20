import Foundation

/// Dock 右键菜单的纯数据描述：与 AppKit 解耦，标题/禁用态逻辑由单元测试覆盖。
enum PlayerMenuAction: Equatable {
    case togglePlayback
    case previous
    case next
}

enum PlayerMenuSpecItem: Equatable {
    /// 歌名等主信息行（加粗展示、不可点按）。
    case headline(String)
    /// 歌手/专辑等次信息行（次要颜色、不可点按）。
    case subline(String)
    case separator
    /// 可点按命令：标题 + SF Symbol + 动作。
    case command(title: String, symbol: String, action: PlayerMenuAction, isEnabled: Bool)
}

enum PlayerMenuSpec {
    static let noTrackPlaceholder = "未在播放"

    /// `title` 为空视为无曲目：信息行显示占位文案且三条命令全部禁用；
    /// 播放/暂停命令的标题与图标随 `isPlaying` 切换。
    static func items(title: String?, subtitle: String?, isPlaying: Bool) -> [PlayerMenuSpecItem] {
        let hasTrack = !(title ?? "").isEmpty
        var items: [PlayerMenuSpecItem] = []
        if hasTrack, let title {
            items.append(.headline(title))
            if let subtitle, !subtitle.isEmpty {
                items.append(.subline(subtitle))
            }
        } else {
            items.append(.headline(noTrackPlaceholder))
        }

        items.append(.separator)
        items.append(.command(
            title: isPlaying ? "暂停" : "播放",
            symbol: isPlaying ? "pause.fill" : "play.fill",
            action: .togglePlayback,
            isEnabled: hasTrack
        ))
        items.append(.command(title: "上一首", symbol: "backward.fill", action: .previous, isEnabled: hasTrack))
        items.append(.command(title: "下一首", symbol: "forward.fill", action: .next, isEnabled: hasTrack))
        return items
    }
}
