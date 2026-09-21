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
            // 记住上次窗口大小与位置：有存档时先恢复，再做超屏收缩兜底；
            // 无存档（首次启动）时 setFrameUsingName 返回 false，保留默认 1080x650。
            // frameAutosaveName 在当前 SDK 是只读属性，用同名方法设置。
            window.setFrameUsingName(Self.windowFrameAutosaveName)
            window.setFrameAutosaveName(Self.windowFrameAutosaveName)
            offsetTrafficLights(of: window)

            let current = window.frame
            // 存档可能来自老版本或被外部写坏：恢复后双向钳制——超屏收缩，
            // 小于最小尺寸（840×520）则放大，避免播放条落入异常窄宽布局。
            let targetWidth = min(max(current.width, 840), maxWidth)
            let targetHeight = min(max(current.height, 520), maxHeight)
            guard targetWidth != current.width || targetHeight != current.height else { continue }

            // 尺寸被钳制时（存档过小）整体居中；仅超屏收缩时保留原位置锚点。
            let needsCentering = current.width < 840 || current.height < 520
            let target: NSRect
            if needsCentering {
                target = NSRect(
                    x: visible.minX + (visible.width - targetWidth) / 2,
                    y: visible.minY + (visible.height - targetHeight) / 2,
                    width: targetWidth,
                    height: targetHeight
                )
            } else {
                // NSRect 原点在左下：保持左上角不动，仅从右/下边收缩。
                target = NSRect(
                    x: current.minX,
                    y: current.maxY - targetHeight,
                    width: targetWidth,
                    height: targetHeight
                )
            }
            window.setFrame(target, display: true, animate: false)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows.first(where: { $0.isVisible })?.makeFirstResponder(nil)
        }
    }

    /// 窗口大小/位置存档名（NSWindow 自动在 UserDefaults 保存与恢复）。
    private static let windowFrameAutosaveName = "ManyuMusic.mainWindow"

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
