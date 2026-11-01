import SwiftUI

struct AppInfo {
    var name = ""
    var icon = "Icon"
    var accent = Accent.standard
    var appearance = Appearance.system
}

extension EnvironmentValues {
    @Entry var appInfo = AppInfo()
}

public extension View {
    /// Put on the root view of the app's window. Applies the chosen theme and colour, provides `Account.shared`,
    /// and covers the app with the sign-in screen until it's answered.
    ///
    /// - Parameters:
    ///   - name: Shown on the sign-in screen and the account page.
    ///   - icon: An image set with the app icon, for the sign-in screen.
    ///   - accent: The colour until one is picked, as hex.
    ///   - appearance: The theme until one is picked.
    ///   - showsSignIn: False for a scene other than the main window, such as Settings or a menu bar extra.
    func azaUI(name: String, icon: String = "Icon", accent: String = Accent.standard,
               appearance: Appearance = .system, showsSignIn: Bool = true) -> some View {
        modifier(Root(info: AppInfo(name: name, icon: icon, accent: accent, appearance: appearance), showsSignIn: showsSignIn))
    }
}

private struct Root: ViewModifier {
    let info: AppInfo
    let showsSignIn: Bool
    @State private var account = Account.shared
    @AppStorage private var accent: String
    @AppStorage private var appearance: Appearance

    init(info: AppInfo, showsSignIn: Bool) {
        self.info = info
        self.showsSignIn = showsSignIn
        _accent = AppStorage(wrappedValue: info.accent, Accent.key)
        _appearance = AppStorage(wrappedValue: info.appearance, Appearance.key)
    }

    func body(content: Content) -> some View {
        content
            .modifier(Shared(info: info, accent: accent, account: account))
            .onChange(of: appearance, initial: true) { appearance.apply() }
            #if os(iOS)
            .fullScreenCover(isPresented: .constant(showsSignIn && !account.answered)) { cover }
            #else
            .sheet(isPresented: .constant(showsSignIn && !account.answered)) { cover }
            #endif
    }

    /// Presentations don't reliably inherit the environment set above them, so the cover gets its own.
    private var cover: some View {
        SignInScreen().modifier(Shared(info: info, accent: accent, account: account))
    }
}

private struct Shared: ViewModifier {
    let info: AppInfo
    let accent: String
    let account: Account

    func body(content: Content) -> some View {
        content
            .tint(Color(hex: accent))
            .environment(\.accent, Color(hex: accent))
            .environment(\.onAccent, Accent.on(accent))
            .environment(\.appInfo, info)
            .environment(account)
    }
}
