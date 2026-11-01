import SwiftUI

/// The app's colour, stored as six hex digits under the `accent` key.
public enum Accent {
    /// White in dark mode and black in light mode, so it always stands out from the background.
    public static let standard = "FFFFFF"
    public static let presets = [standard, "FF375F", "FF9F0A", "30D158", "0A84FF", "5E5CE6"]
    public static let key = "accent"

    /// Black on light accents, white on dark ones.
    public static func on(_ hex: String) -> Color {
        if hex == standard { return Color.adaptive(light: .white, dark: .black) }
        let (r, g, b) = components(hex)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.55 ? .black : .white
    }

    /// For VoiceOver.
    static func name(_ hex: String) -> String {
        switch hex {
        case standard: "Black and white"
        case "FF375F": "Pink"
        case "FF9F0A": "Orange"
        case "30D158": "Green"
        case "0A84FF": "Blue"
        case "5E5CE6": "Indigo"
        default: "Custom"
        }
    }

    static func components(_ hex: String) -> (Double, Double, Double) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFF375F
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

public extension Color {
    /// `Accent.standard` is black or white with the appearance; anything else is that exact colour.
    init(hex: String) {
        if hex == Accent.standard {
            self = .adaptive(light: .black, dark: .white)
            return
        }
        let (r, g, b) = Accent.components(hex)
        self.init(red: r, green: g, blue: b)
    }

    var hex: String {
        let c = resolve(in: EnvironmentValues())
        let byte = { (x: Float) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue))
    }

    /// One colour in light mode and another in dark, following whatever appearance the view is in.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #endif
    }
}

public extension EnvironmentValues {
    /// The app's colour, set at the root by `.azaUI(...)`.
    @Entry var accent: Color = .accentColor
    /// Text and symbols drawn on top of `accent`.
    @Entry var onAccent: Color = .white
}
