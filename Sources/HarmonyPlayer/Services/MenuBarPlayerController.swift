import AppKit
import Combine

/// 菜单栏播放控制：状态项左侧实时显示当前歌词，右侧为播放图标（临时
/// 占位，正式图标设计完成后替换），左键/右键点击均弹出「播放 / 暂停」菜单。
@MainActor
final class MenuBarPlayerController: NSObject {
    static let shared = MenuBarPlayerController()

    static let enabledKey = "ManyuMusic.menuBarPlayer"

    /// 歌词文本的最大展示宽度，超出按菜单栏字体测宽截尾，
    /// 避免一句长歌词占满整条菜单栏挤掉其他应用的状态项。
    private static let maxLyricWidth: CGFloat = 170

    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    private override init() {
        super.init()
    }

    /// 未写过设置时默认开启；启动与设置开关变化后都调用它装卸。
    func syncWithSetting() {
        if isEnabled {
            install()
        } else {
            remove()
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - 状态项装卸

    private func install() {
        if statusItem != nil { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let icon = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放") {
                icon.isTemplate = true
                button.image = icon
            }
            // 歌词在图标前面（左侧），图标贴状态项尾随端。
            button.imagePosition = .imageTrailing
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // 左键与右键都弹菜单。
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        observeLyrics()
    }

    private func remove() {
        cancellables.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - 歌词实时刷新

    /// 曲目 / 歌词 / 播放时间（0.25s tick，桥接在 clock 上）任一变化即重算
    /// 当前句；文本未变不写 title，避免无谓的按钮重绘。
    private func observeLyrics() {
        let player = AudioPlayer.shared
        Publishers.CombineLatest3(
            player.$currentTrack,
            player.$lyricLines,
            player.clock.$currentTime
        )
        .map { _, _, _ in player.currentLyricText ?? "" }
        .removeDuplicates()
        .sink { [weak self] text in
            Task { @MainActor in
                self?.updateLyricTitle(text)
            }
        }
        .store(in: &cancellables)
    }

    private func updateLyricTitle(_ text: String) {
        statusItem?.button?.title = Self.truncatedLyric(text)
    }

    /// 中英文混排宽度差异大，按字符数截断不可靠，改为实测宽度截尾。
    private static func truncatedLyric(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
        func width(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: attributes).width
        }
        guard width(text) > maxLyricWidth else { return text }
        var trimmed = text
        while !trimmed.isEmpty {
            trimmed.removeLast()
            if width(trimmed + "…") <= maxLyricWidth {
                return trimmed + "…"
            }
        }
        return "…"
    }

    // MARK: - 菜单

    /// 每次点击现做菜单，播放状态即时反映到两项的可用态。
    @objc private func statusItemClicked(_ sender: NSStatusBarButton?) {
        guard let item = statusItem else { return }
        item.menu = makeMenu()
        // performClick 会高亮按钮并把菜单贴着状态项弹出；弹出后解除关联，
        // 下次点击仍走 action 由我们重建菜单。
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let player = AudioPlayer.shared
        let hasTrack = player.currentTrack != nil

        let play = NSMenuItem(title: "播放", action: #selector(playTapped), keyEquivalent: "")
        play.target = self
        play.isEnabled = hasTrack && !player.isPlaying
        play.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放")

        let pause = NSMenuItem(title: "暂停", action: #selector(pauseTapped), keyEquivalent: "")
        pause.target = self
        pause.isEnabled = hasTrack && player.isPlaying
        pause.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "暂停")

        let menu = NSMenu()
        menu.addItem(play)
        menu.addItem(pause)
        return menu
    }

    @objc private func playTapped() {
        AudioPlayer.shared.resume()
    }

    @objc private func pauseTapped() {
        AudioPlayer.shared.pause()
    }
}
