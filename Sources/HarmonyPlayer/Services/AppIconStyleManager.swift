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
    static func selectedStyle() -> AppIconStyle {
        let rawValue = UserDefaults.standard.string(forKey: AppIconStyle.storageKey)
        return AppIconStyle(rawValue: rawValue ?? "") ?? .automatic
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
            let appearance = AppAppearance(rawValue: appearanceRaw ?? "") ?? .dark
            if appearance == .system {
                isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            } else {
                isDark = appearance == .dark
            }
        }

        let resolvedStyle: AppIconStyle = isDark ? .dark : .light
        guard let image = image(for: resolvedStyle) else { return }
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
                isDark = true
            }
        }

        let resourceName = isDark ? "AppIconDark" : "AppIconLight"
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: resourceName) ?? NSImage(named: "AppIcon")
    }
}
