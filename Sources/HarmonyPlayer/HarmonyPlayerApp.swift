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
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1080, height: 650)
        Settings {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(player)
                .environmentObject(library)
        }

        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入音乐…") {
                    library.presentImportPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
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

        DispatchQueue.main.async {
            Self.fitWindowsToVisibleScreen()
        }
    }

    private static func fitWindowsToVisibleScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let maxWidth = max(840, visible.width - 32)
        let maxHeight = max(520, visible.height - 32)

        for window in NSApp.windows where window.isVisible {
            window.minSize = NSSize(width: 840, height: 520)

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
