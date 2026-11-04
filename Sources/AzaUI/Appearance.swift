import SwiftUI

/// Light, dark, or whatever the system is set to. Stored under the `appearance` key.
nonisolated public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    /// OLED Dark: dark with pure black behind everything. The Mac only; the iPhone's dark is already black.
    case system, light, dark, oledDark

    public static let key = "appearance"
    public var id: Self { self }
    public var title: String { self == .oledDark ? "OLED Dark" : rawValue.capitalized }

    /// The themes to pick from here.
    public static var choices: [Appearance] {
        #if os(macOS)
        allCases
        #else
        [.system, .light, .dark]
        #endif
    }

    /// Set on every window rather than with `preferredColorScheme`, which doesn't reach a sheet that's already open.
    @MainActor func apply() {
        #if os(iOS)
        let style: UIUserInterfaceStyle = switch self {
        case .system: .unspecified
        case .light: .light
        case .dark, .oledDark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
        #else
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark, .oledDark: NSAppearance(named: .darkAqua)
        }
        #endif
    }
}
