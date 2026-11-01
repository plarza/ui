import SwiftUI

/// What the shared screens need to know about the app they're in.
public struct AzaApp: Sendable {
    /// Shown on the sign-in screen.
    public var name: String
    /// An image set in the app's asset catalog with the app icon, for the sign-in screen.
    public var icon: String
    /// The colour until one is picked in Profile.
    public var accent: String
    /// The appearance until one is picked in Profile.
    public var appearance: Appearance

    public init(name: String, icon: String = "Icon", accent: String = Accent.standard, appearance: Appearance = .system) {
        self.name = name
        self.icon = icon
        self.accent = accent
        self.appearance = appearance
    }
}

public extension EnvironmentValues {
    @Entry var azaApp = AzaApp(name: "")
}

public extension View {
    /// Put on the root view of the app's window: applies the chosen colour and appearance, provides the aza account,
    /// and covers the app with the sign-in screen until it has been answered.
    func aza(_ app: AzaApp, account: AzaAccount = .shared) -> some View {
        modifier(AzaRoot(app: app, account: account))
    }
}

private struct AzaRoot: ViewModifier {
    let app: AzaApp
    @Bindable var account: AzaAccount
    @AppStorage private var accent: String
    @AppStorage private var appearance: Appearance

    init(app: AzaApp, account: AzaAccount) {
        self.app = app
        self.account = account
        _accent = AppStorage(wrappedValue: app.accent, Accent.key)
        _appearance = AppStorage(wrappedValue: app.appearance, Appearance.key)
    }

    func body(content: Content) -> some View {
        let color = Color(hex: accent)
        content
            .tint(color)
            .environment(\.accent, color)
            .environment(\.onAccent, Accent.on(accent))
            .environment(\.azaApp, app)
            .environment(account)
            .onChange(of: appearance, initial: true) { appearance.apply() }
            #if os(iOS)
            .fullScreenCover(isPresented: .constant(!account.decided)) { cover }
            #else
            .sheet(isPresented: .constant(!account.decided)) { cover }
            #endif
    }

    private var cover: some View {
        SignInScreen()
            .tint(Color(hex: accent))
            .environment(\.accent, Color(hex: accent))
            .environment(\.onAccent, Accent.on(accent))
            .environment(\.azaApp, app)
            .environment(account)
    }
}
