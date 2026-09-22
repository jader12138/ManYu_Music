import AppKit
import SwiftUI

@main
struct HarmonyPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryStore()
    @StateObject private var player = AudioPlayer.shared
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
        .defaultSize(width: FixedWindowLayout.size.width, height: FixedWindowLayout.size.height)
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

                Menu("播放模式") {
                    ForEach(PlaybackMode.allCases, id: \.rawValue) { mode in
                        Button {
                            player.setPlaybackMode(mode)
                        } label: {
                            if player.playbackMode == mode {
                                Label(mode.helpText, systemImage: "checkmark")
                            } else {
                                Text(mode.helpText)
                            }
                        }
                    }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // —— 状态栏黑底根因级修复 ——
        // 告诉系统整个 App 是深色 appearance，系统就不会给状态栏宿主 window
        // 的 NSNextStepFrame 画 0.129 gray 深灰胶囊（状态栏"黑色蒙版"来源）。
        // SwiftUI 的 .preferredColorScheme() 仍会覆盖 individual window 的 appearance，
        // 所以主页浅色、播放页深色正常显示。
        NSApp.appearance = NSAppearance(named: .darkAqua)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 启动第一步固定 Dock 图标为上一次会话的具体样式（深色/浅色），
        // 不在启动早期解析外观（SwiftUI 首窗创建前 effectiveAppearance 可能不准），
        // 避免图标跳变；待外观环境稳定后再校正一次——两次会话之间外观没变时
        // 解析结果相同，不会有可见切换。
        AppIconStyleManager.applyLastUsedIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            AppIconStyleManager.apply()
        }

        // 内存压力兜底：长期挂机听歌时，系统内存吃紧时自动清空可再生成缓存。
        MemoryPressureMonitor.install()

        Self.installScrollbarHider()

        MenuBarPlayerController.shared.syncWithSetting()

        // 一次性清掉历史窗口自动存档（含被写坏的 185×24 框架与
        // SwiftUI 按视图类型名自存的框架），之后窗口一律按固定布局启动。
        Self.migrateLegacyWindowFramesIfNeeded()

        DispatchQueue.main.async {
            Self.fitWindowsToVisibleScreen()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Self.fitWindowsToVisibleScreen()
        }
        // SwiftUI WindowGroup 的状态恢复可能晚于首屏再写一次框架，
        // 0.9 秒再校正一次，保证每次启动都落在固定位置与尺寸。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
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
        for window in NSApp.windows where window.isVisible {
            window.toolbar = nil
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            // 排除出窗口列表：否则 Dock 右键菜单顶部会多一条系统自动加的
            // 窗口标题项（应用名 + 对勾），与自定义播放菜单叠在一起。
            window.isExcludedFromWindowsMenu = true
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

            // 主窗口（titled 常规窗口；状态栏等 NSPanel 不含 titled）每次启动
            // 强制落到固定位置与固定尺寸，不读取任何自动存档。
            if window.styleMask.contains(.titled) {
                applyFixedFrame(to: window)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows.first(where: { $0.isVisible })?.makeFirstResponder(nil)
        }
    }

    /// 把窗口放到用户指定的固定布局：1060×706，屏幕左上角起 (568, 193)。
    /// 位置按窗口当前所在屏幕换算（换屏/分辨率变化仍正确），放不下时
    /// 等比收缩并夹回可见区域（菜单栏/Dock 内），保证任何环境下窗口完整可见。
    private static func applyFixedFrame(to window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame

        let targetWidth = min(FixedWindowLayout.size.width, visible.width)
        let targetHeight = min(FixedWindowLayout.size.height, visible.height)

        // 固定位置以「屏幕左上角」为原点计量（System Events 坐标系）；
        // NSWindow 原点在左下角，用屏幕全框（含菜单栏高度）换算。
        var origin = NSPoint(
            x: screen.frame.minX + FixedWindowLayout.topLeft.x,
            y: screen.frame.maxY - FixedWindowLayout.topLeft.y - targetHeight
        )
        // 夹到可见区域内：窗口任何边都不允许被菜单栏、Dock 或屏幕边缘裁掉。
        origin.x = min(max(origin.x, visible.minX), visible.maxX - targetWidth)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - targetHeight)

        let target = NSRect(origin: origin, size: NSSize(width: targetWidth, height: targetHeight))
        if window.frame != target {
            window.setFrame(target, display: true, animate: false)
        }
    }

    /// 删除被写坏的历史窗口框架存档，只执行一次。
    /// 旧逻辑曾从 `ManyuMusic.mainWindow` 恢复出一个 185×24 的畸形框架
    /// （疑似旧外接屏残留），是窗口启动后跑到屏幕右上角的直接原因。
    private static func migrateLegacyWindowFramesIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "ManyuMusic.fixedWindowLayout.v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        defaults.removeObject(forKey: "NSWindow Frame ManyuMusic.mainWindow")
        defaults.removeObject(forKey: "NSWindow Frame ManyuMusic.statsWindow")
        // SwiftUI WindowGroup 按根视图类型名自动保存的框架键。
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("NSWindow Frame SwiftUI.ModifiedContent<") {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: migrationKey)
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
        // 开启"关闭窗口后继续后台播放"时，点红叉只隐藏窗口、不退出应用，
        // 音乐继续播放；用户可通过点击 Dock 图标重新打开窗口。
        let keepPlaying = UserDefaults.standard.bool(
            forKey: AudioPlayer.keepPlayingAfterWindowCloseKey
        )
        return !keepPlaying
    }

    /// 点击 Dock 图标重新打开主窗口（后台播放模式下关闭窗口后，Dock 仍可唤回）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    /// Dock 图标右键菜单：每次右键系统都会重新取一份新菜单，
    /// 歌曲信息与播放/暂停文案即时反映当前状态。
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        DockMenuController.shared.makeMenu()
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

/// 主窗口固定启动布局（2026-09-22 由用户按实际摆放确认）。
/// 位置以主屏左上角为原点（与 System Events 量到的坐标一致）：
/// 左上角 (568, 193)，尺寸 1060×706。每次启动强制套用，不记忆用户改动。
enum FixedWindowLayout {
    static let size = NSSize(width: 1060, height: 706)
    static let topLeft = NSPoint(x: 568, y: 193)
}
