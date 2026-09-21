import AppKit
import Combine

/// 菜单栏播放控制：两个相邻状态项——左侧固定宽度区域实时显示当前歌词
/// （纯展示，点击无反应、无高亮底色），右侧为播放图标（主人设计的 SVG
/// 主体，模板图自适配深浅色），左键/右键点击图标弹出「播放 / 暂停」菜单。
@MainActor
final class MenuBarPlayerController: NSObject {
    static let shared = MenuBarPlayerController()

    static let enabledKey = "ManyuMusic.menuBarPlayer"

    /// 歌词区固定宽度：逐句更新只改文本、不改变状态项宽度，
    /// 避免可变宽度下菜单栏区域反复伸缩造成的闪烁。
    fileprivate static let lyricWidth: CGFloat = 160

    private var lyricItem: NSStatusItem?
    private var iconItem: NSStatusItem?
    private var menu: NSMenu?
    private var cancellables: Set<AnyCancellable> = []
    /// LRC 常有整句留白的间隙行；留白期间沿用上一句，
    /// 避免歌词区整块隐藏/重现的闪烁。
    private var lastLyricText = ""

    private struct LyricState: Equatable {
        let hasLyrics: Bool
        let text: String
    }

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
        guard iconItem == nil else { return }

        // 延迟创建：启动早期菜单栏尚未完成布局，过早注册状态项会被系统忽略。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.iconItem == nil else { return }

            // 歌词项：用 button 而非自定义 view（NSStatusItem.view 在当前
            // macOS 版本下创建后状态项完全不可见）。去掉 isBordered 和
            // showsBorderOnlyWhileMouseInside 消除点击黑底，contentTintColor
            // 跟随 labelColor 自动适配深浅色菜单栏。
            let lyricItem = NSStatusBar.system.statusItem(withLength: Self.lyricWidth)
            if let button = lyricItem.button {
                button.isBordered = false
                button.showsBorderOnlyWhileMouseInside = false
                button.bezelStyle = .regularSquare
                button.imagePosition = .noImage
                button.font = NSFont.menuBarFont(ofSize: 0)
                button.contentTintColor = NSColor.labelColor
                button.lineBreakMode = .byTruncatingTail
                button.allowsExpansionToolTips = true
            }
            self.lyricItem = lyricItem

            // 图标项：挂常驻菜单，左右键点击均可弹出，弹出前现做内容。
            let iconItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            iconItem.button?.image = MenuBarLogo.makeIcon()
            iconItem.button?.image?.isTemplate = true
            iconItem.button?.imagePosition = .imageOnly
            iconItem.button?.isBordered = false
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            iconItem.menu = menu
            self.iconItem = iconItem
            self.menu = menu

            self.observeLyrics()
        }
    }

    private func remove() {
        cancellables.removeAll()
        lastLyricText = ""
        if let lyricItem {
            NSStatusBar.system.removeStatusItem(lyricItem)
            self.lyricItem = nil
        }
        if let iconItem {
            NSStatusBar.system.removeStatusItem(iconItem)
            self.iconItem = nil
        }
        menu = nil
    }

    // MARK: - 歌词实时刷新

    /// 曲目 / 歌词 / 播放时间（0.25s tick，桥接在 clock 上）任一变化即重算
    /// 当前句；无歌词时整区隐藏，间隙留白沿用上一句。
    private func observeLyrics() {
        let player = AudioPlayer.shared
        Publishers.CombineLatest3(
            player.$currentTrack,
            player.$lyricLines,
            player.clock.$currentTime
        )
        .map { (track, lines, _) -> LyricState in
            LyricState(hasLyrics: track != nil && !lines.isEmpty, text: player.currentLyricText ?? "")
        }
        .removeDuplicates()
        .sink { [weak self] state in
            Task { @MainActor in
                self?.handleLyricChange(hasLyrics: state.hasLyrics, text: state.text)
            }
        }
        .store(in: &cancellables)
    }

    private func handleLyricChange(hasLyrics: Bool, text: String) {
        if !hasLyrics {
            lastLyricText = ""
        } else if !text.isEmpty {
            lastLyricText = text
        }
        lyricItem?.button?.title = lastLyricText
        lyricItem?.isVisible = !lastLyricText.isEmpty
    }
}

// MARK: - 菜单

extension MenuBarPlayerController: NSMenuDelegate {
    /// 每次弹出前重建，播放状态即时反映到两项的可用态。
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
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

        menu.addItem(play)
        menu.addItem(pause)
    }

    @objc private func playTapped() {
        AudioPlayer.shared.resume()
    }

    @objc private func pauseTapped() {
        AudioPlayer.shared.pause()
    }
}
