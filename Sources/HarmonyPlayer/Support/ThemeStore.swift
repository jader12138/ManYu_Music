import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "白天模式"
        case .dark: "夜间模式"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let appearanceKey = "ManyuMusic.appearance"

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            DispatchQueue.main.async {
                AppIconStyleManager.apply()
            }
        }
    }

    init() {
        let rawValue = UserDefaults.standard.string(forKey: Self.appearanceKey)
        // 默认跟随系统：首次安装时系统为浅色则软件呈白色模式（白天），
        // 系统为深色则软件呈夜间模式。用户可在设置里手动固定为白天/夜间。
        appearance = AppAppearance(rawValue: rawValue ?? "") ?? .system
    }

    func toggleDayNight() {
        appearance = appearance == .dark ? .light : .dark
    }
}
