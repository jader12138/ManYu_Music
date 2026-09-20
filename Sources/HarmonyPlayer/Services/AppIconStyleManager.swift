import AppKit
import SwiftUI

/// 系统当前是否为深色外观。单元测试进程没有初始化 NSApplication，`NSApp`
/// 全局常量为 nil（隐式解包直接崩溃），此时按默认浅色（白色模式）返回 false。
private func hpSystemIsDarkAppearance() -> Bool {
    NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

extension Notification.Name {
    /// `NSApp.applicationIconImage` 刚被替换（主题图标或 Dock 封面模式）。
    /// 菜单栏等镜像展示该图标的地方收到后刷新，避免引用过期图像。
    static let appIconDidChange = Notification.Name("ManyuMusic.appIconDidChange")
}

enum AppIconStyle: String, CaseIterable, Identifiable {
    case automatic
    case dark
    case light

    static let storageKey = "ManyuMusic.appIconStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .dark: "深色"
        case .light: "浅色"
        }
    }

    var resourceName: String {
        switch self {
        case .automatic: "AppIconDark"
        case .dark: "AppIconDark"
        case .light: "AppIconLight"
        }
    }
}

@MainActor
enum AppIconStyleManager {
    /// 上一次解析出的具体图标（深色/浅色）。启动时直接恢复它，
    /// 避免启动早期外观解析（SwiftUI 首窗创建前 effectiveAppearance 可能不准）
    /// 与主题加载之间出现 Dock 图标跳变。
    private static let lastResolvedStyleKey = "ManyuMusic.lastResolvedAppIconStyle"

    static func selectedStyle() -> AppIconStyle {
        if let rawValue = UserDefaults.standard.string(forKey: AppIconStyle.storageKey) {
            if rawValue == "albumArtwork" {
                UserDefaults.standard.set(true, forKey: DockArtworkController.showsArtworkKey)
                UserDefaults.standard.set(AppIconStyle.automatic.rawValue, forKey: AppIconStyle.storageKey)
                return .automatic
            }
            if let style = AppIconStyle(rawValue: rawValue) {
                return style
            }
        }
        return .automatic
    }

    static func apply() {
        let style = selectedStyle()
        let isDark: Bool
        switch style {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .automatic:
            let appearanceRaw = UserDefaults.standard.string(forKey: ThemeStore.appearanceKey)
            let appearance = AppAppearance(rawValue: appearanceRaw ?? "") ?? .system
            if appearance == .system {
                isDark = hpSystemIsDarkAppearance()
            } else {
                isDark = appearance == .dark
            }
        }

        let resolvedStyle: AppIconStyle = isDark ? .dark : .light
        UserDefaults.standard.set(resolvedStyle.rawValue, forKey: lastResolvedStyleKey)
        guard let image = image(for: resolvedStyle) else { return }
        NSApplication.shared.applicationIconImage = image
        NSApplication.shared.dockTile.display()
        NotificationCenter.default.post(name: .appIconDidChange, object: nil)
    }

    /// 启动第一步调用：直接恢复上一次会话解析出的具体图标（深色/浅色），
    /// 不做任何外观解析。首次启动没有记录时回退到正常解析。
    static func applyLastUsedIcon() {
        guard let rawValue = UserDefaults.standard.string(forKey: lastResolvedStyleKey),
              let style = AppIconStyle(rawValue: rawValue),
              style == .dark || style == .light,
              let image = image(for: style) else {
            apply()
            return
        }
        NSApplication.shared.applicationIconImage = image
        NSApplication.shared.dockTile.display()
        NotificationCenter.default.post(name: .appIconDidChange, object: nil)
    }

    static func image(for style: AppIconStyle, colorScheme: ColorScheme? = nil) -> NSImage? {
        let isDark: Bool
        switch style {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .automatic:
            if let colorScheme {
                isDark = colorScheme == .dark
            } else if let appearanceRaw = UserDefaults.standard.string(forKey: ThemeStore.appearanceKey),
                      let appearance = AppAppearance(rawValue: appearanceRaw) {
                if appearance == .system {
                    isDark = hpSystemIsDarkAppearance()
                } else {
                    isDark = appearance == .dark
                }
            } else {
                // appearance 未设过时默认跟随系统浅色（白色模式），与 ThemeStore 默认 .system 一致
                isDark = hpSystemIsDarkAppearance()
            }
        }

        let resourceName = isDark ? "AppIconDark" : "AppIconLight"
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: resourceName) ?? NSImage(named: "AppIcon")
    }
}
