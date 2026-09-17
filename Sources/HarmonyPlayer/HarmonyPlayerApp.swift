import AppKit
import SwiftUI

@main
struct HarmonyPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryStore()
    @StateObject private var player = AudioPlayer()
    @StateObject private var theme = ThemeStore()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(theme)
                .preferredColorScheme(theme.appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 650)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("播放") {
                Button(player.isPlaying ? "暂停" : "播放") {
                    player.togglePlayback()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(player.currentTrack == nil)

                Divider()

                Button("下一首") {
                    player.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player.queue.isEmpty)

                Button("上一首") {
                    player.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(player.queue.isEmpty)

                Button("快进 10 秒") {
                    player.seek(to: player.currentTime + 10)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(player.currentTrack == nil)

                Button("后退 10 秒") {
                    player.seek(to: player.currentTime - 10)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(player.currentTrack == nil)

                Divider()

                Menu("循环模式") {
                    ForEach(RepeatMode.allCases, id: \.rawValue) { mode in
                        Button {
                            player.repeatMode = mode
                        } label: {
                            if player.repeatMode == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }

                Toggle("随机播放", isOn: $player.isShuffle)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppIconStyleManager.apply()

        Self.installScrollbarHider()

        DispatchQueue.main.async {
            Self.fitWindowsToVisibleScreen()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Self.fitWindowsToVisibleScreen()
        }
    }

    // MARK: - 全局隐藏滚动条

    /// 所有界面都不显示滚动条（滚动功能本身不受影响，触控板/滚轮照常使用）。
    /// SwiftUI 的 ScrollView/List 懒创建底层 NSScrollView，因此用低频扫描 +
    /// 窗口成为主窗口时扫描，保证切换页面后新出现的滚动视图也被覆盖。
    private static func installScrollbarHider() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            hideScrollbarsInAllWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            hideScrollbarsInAllWindows()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { _ in
            hideScrollbarsInAllWindows()
        }
    }

    private static func hideScrollbarsInAllWindows() {
        for window in NSApp.windows where window.isVisible {
            hideScrollbars(in: window.contentView)
        }
    }

    private static func hideScrollbars(in view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView {
            // 只在仍处于开启状态时才写回：重复赋值会触发 NSScrollView 重新布局，
            // 在滚动进行中表现为周期性顿挫。
            if scrollView.hasVerticalScroller {
                scrollView.hasVerticalScroller = false
            }
            if scrollView.hasHorizontalScroller {
                scrollView.hasHorizontalScroller = false
            }
        }
        for subview in view.subviews {
            hideScrollbars(in: subview)
        }
    }

    private static func fitWindowsToVisibleScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let maxWidth = max(840, visible.width - 32)
        let maxHeight = max(520, visible.height - 32)

        for window in NSApp.windows where window.isVisible {
            window.toolbar = nil
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            if let frameView = window.contentView?.superview {
                frameView.wantsLayer = true
                frameView.layer?.backgroundColor = NSColor.clear.cgColor
                frameView.layer?.isOpaque = false
            }
            window.minSize = NSSize(width: 840, height: 520)
            offsetTrafficLights(of: window)

            let current = window.frame
            let targetWidth = min(current.width, maxWidth)
            let targetHeight = min(current.height, maxHeight)
            guard targetWidth != current.width || targetHeight != current.height else { continue }

            let target = NSRect(
                x: visible.minX + (visible.width - targetWidth) / 2,
                y: visible.minY + (visible.height - targetHeight) / 2,
                width: targetWidth,
                height: targetHeight
            )
            window.setFrame(target, display: true, animate: false)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows.first(where: { $0.isVisible })?.makeFirstResponder(nil)
        }
    }

    /// 窗口尺寸变化后重新应用交通灯偏移（带 identifier 防止重复累加）。
    private static let trafficLightResizeObserver: Void = {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            offsetTrafficLights(of: window)
        }
    }()

    /// 把窗口左上角的红黄绿三键整体往右、往下挪一点，避免过于贴住左上角。
    private static func offsetTrafficLights(of window: NSWindow) {
        _ = trafficLightResizeObserver
        let dx: CGFloat = 6
        let dy: CGFloat = -6
        let marker = NSUserInterfaceItemIdentifier("ManyuMusic.trafficLightOffset")
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            guard button.identifier != marker else { continue }
            var frame = button.frame
            button.setFrameOrigin(NSPoint(x: frame.origin.x + dx, y: frame.origin.y + dy))
            button.identifier = marker
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private extension RepeatMode {
    var title: String {
        switch self {
        case .off: "关闭循环"
        case .all: "列表循环"
        case .one: "单曲循环"
        }
    }
}
