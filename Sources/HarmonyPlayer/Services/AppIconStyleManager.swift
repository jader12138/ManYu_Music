import AppKit
import SwiftUI

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
                isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            } else {
                isDark = appearance == .dark
            }
        }

        let resolvedStyle: AppIconStyle = isDark ? .dark : .light
        UserDefaults.standard.set(resolvedStyle.rawValue, forKey: lastResolvedStyleKey)
        guard let image = image(for: resolvedStyle) else { return }
        NSApplication.shared.applicationIconImage = image
        NSApplication.shared.dockTile.display()
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
                    isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                } else {
                    isDark = appearance == .dark
                }
            } else {
                // appearance 未设过时默认跟随系统浅色（白色模式），与 ThemeStore 默认 .system 一致
                isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }

        let resourceName = isDark ? "AppIconDark" : "AppIconLight"
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: resourceName) ?? NSImage(named: "AppIcon")
    }
}
