import AppKit
import SwiftUI

/// 菜单栏迷你播放器：NSStatusItem 展示应用图标（与 Dock 图标同步，含专辑
/// 封面模式），左键弹出迷你播放面板；点击面板外自动收起（transient）。
@MainActor
final class MenuBarPlayerController: NSObject {
    static let shared = MenuBarPlayerController()

    static let enabledKey = "ManyuMusic.menuBarPlayer"

    /// 菜单栏图标边长：与系统状态项图标（Wi-Fi/音量）同档。
    private static let iconSide: CGFloat = 17

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var iconObserver: NSObjectProtocol?

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MiniPlayerView(player: AudioPlayer.shared)
        )
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
        if let statusItem {
            refreshIcon()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        observeIconChanges()
        refreshIcon()
    }

    private func remove() {
        if let iconObserver {
            NotificationCenter.default.removeObserver(iconObserver)
            self.iconObserver = nil
        }
        popover.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - 图标

    /// Dock 图标被替换（主题/封面模式/播放状态）时同步刷新菜单栏图标。
    private func observeIconChanges() {
        guard iconObserver == nil else { return }
        iconObserver = NotificationCenter.default.addObserver(
            forName: .appIconDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIcon()
            }
        }
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        button.image = Self.menuBarIcon(from: NSApp?.applicationIconImage)
        button.imageScaling = .scaleProportionallyUpOrDown
    }

    /// 把当前应用图标重绘为菜单栏尺寸（等比裁满方形，保留内置透明边与圆角）。
    private static func menuBarIcon(from icon: NSImage?) -> NSImage? {
        guard let icon, icon.size.width > 0, icon.size.height > 0 else { return nil }
        let side = iconSide
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        // 图标源图均为方形，这里仍按 aspect-fill 裁剪，防御非方形源图。
        let sourceAspect = icon.size.width / icon.size.height
        let sourceRect: NSRect
        if sourceAspect > 1 {
            let width = icon.size.height
            sourceRect = NSRect(
                x: (icon.size.width - width) / 2,
                y: 0,
                width: width,
                height: icon.size.height
            )
        } else {
            let height = icon.size.width
            sourceRect = NSRect(
                x: 0,
                y: (icon.size.height - height) / 2,
                width: icon.size.width,
                height: height
            )
        }
        icon.draw(
            in: NSRect(origin: .zero, size: NSSize(width: side, height: side)),
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - 弹窗

    @objc private func togglePopover(_ sender: NSStatusBarButton?) {
        guard let button = sender ?? statusItem?.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            refreshIcon()
            syncAppearance()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// 弹窗外观跟随 App 内主题（而非系统外观）：App 固定夜间时弹窗也呈夜间。
    private func syncAppearance() {
        let appearance = AppAppearance(
            rawValue: UserDefaults.standard.string(forKey: ThemeStore.appearanceKey) ?? ""
        ) ?? .system
        switch appearance {
        case .system:
            popover.appearance = nil
        case .light:
            popover.appearance = NSAppearance(named: .vibrantLight)
        case .dark:
            popover.appearance = NSAppearance(named: .vibrantDark)
        }
    }
}
