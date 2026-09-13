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
    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: storageKey)
        }
    }

    private let storageKey = "ManyuMusic.appearance"

    init() {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        appearance = AppAppearance(rawValue: rawValue ?? "") ?? .dark
    }

    func toggleDayNight() {
        appearance = appearance == .dark ? .light : .dark
    }
}
