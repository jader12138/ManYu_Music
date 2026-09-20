import AppKit

/// Dock 图标右键菜单。每次右键系统都会重新调用 `applicationDockMenu`
/// 取一份新菜单，因此内容即时反映当前曲目与播放状态，无需常驻观察。
@MainActor
final class DockMenuController {
    static let shared = DockMenuController()

    private init() {}

    func makeMenu() -> NSMenu {
        let player = AudioPlayer.shared
        let spec = PlayerMenuSpec.items(
            title: player.currentTrack?.displayTitle,
            subtitle: Self.subtitle(for: player.currentTrack),
            isPlaying: player.isPlaying
        )

        let menu = NSMenu()
        for item in spec {
            switch item {
            case .headline(let text):
                let menuItem = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                menuItem.isEnabled = false
                menuItem.attributedTitle = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: NSFontManager.shared.convert(
                            NSFont.menuFont(ofSize: 0),
                            toHaveTrait: .boldFontMask
                        )
                    ]
                )
                menu.addItem(menuItem)
            case .subline(let text):
                let menuItem = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                menuItem.isEnabled = false
                menuItem.attributedTitle = NSAttributedString(
                    string: text,
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
                menu.addItem(menuItem)
            case .separator:
                menu.addItem(.separator())
            case .command(let title, let symbol, let action, let isEnabled):
                let menuItem = NSMenuItem(
                    title: title,
                    action: selector(for: action),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.isEnabled = isEnabled
                menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    /// 副标题：歌手 · 专辑；专辑未填写时只显示歌手。
    private static func subtitle(for track: Track?) -> String? {
        guard let track else { return nil }
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if album.isEmpty {
            return track.displayArtist
        }
        return "\(track.displayArtist) · \(track.displayAlbum)"
    }

    private func selector(for action: PlayerMenuAction) -> Selector {
        switch action {
        case .togglePlayback: return #selector(togglePlayback)
        case .previous: return #selector(previousTrack)
        case .next: return #selector(nextTrack)
        }
    }

    @objc private func togglePlayback() {
        AudioPlayer.shared.togglePlayback()
    }

    @objc private func previousTrack() {
        AudioPlayer.shared.previous()
    }

    @objc private func nextTrack() {
        AudioPlayer.shared.next()
    }
}
