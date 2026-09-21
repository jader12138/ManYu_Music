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
    private var lyricView: LyricStatusView?
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

        // 歌词项：纯文本自定义视图，不经过 NSButton/NSCell 的
        // 高亮与 bezel 绘制路径，点击零反应、零底色。
        let lyricItem = NSStatusBar.system.statusItem(withLength: Self.lyricWidth)
        let lyricView = LyricStatusView(frame: NSRect(x: 0, y: 0, width: Self.lyricWidth, height: NSStatusBar.system.thickness))
        lyricView.setAccessibilityLabel("当前歌词")
        lyricItem.view = lyricView
        self.lyricItem = lyricItem
        self.lyricView = lyricView

        // 图标项：挂常驻菜单，左右键点击均可弹出，弹出前现做内容。
        let iconItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        iconItem.button?.image = MenuBarLogo.makeIcon()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        iconItem.menu = menu
        self.iconItem = iconItem
        self.menu = menu

        observeLyrics()
    }

    private func remove() {
        cancellables.removeAll()
        lastLyricText = ""
        if let lyricItem {
            NSStatusBar.system.removeStatusItem(lyricItem)
            self.lyricItem = nil
            lyricView = nil
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
        lyricView?.text = lastLyricText
        lyricItem?.isVisible = !lastLyricText.isEmpty
    }
}

/// 歌词状态项的自定义视图：只绘制文本，不绘制任何背景，
/// 不经过 NSButton/NSCell 的高亮与 bezel 路径——点击零反应、零底色。
/// 文字颜色用 labelColor 随菜单栏深浅外观自动切换。
private final class LyricStatusView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: MenuBarPlayerController.lyricWidth, height: NSStatusBar.system.thickness)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let size = (text as NSString).boundingRect(
            with: rect.size,
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).size
        // 单行文本在状态项高度内垂直居中。
        let centered = NSRect(
            x: 0,
            y: (bounds.height - size.height) / 2,
            width: bounds.width,
            height: size.height
        )
        (text as NSString).draw(
            with: centered,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
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
