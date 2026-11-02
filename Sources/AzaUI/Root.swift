import SwiftUI

struct AppInfo {
    var name = ""
    var icon = "Icon"
    var accent = Accent.standard
    var appearance = Appearance.system
    var appID: String?
    var scopes = ["sign-in"]
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
    ///   - appID: The app's aza app ID, a domain whose universal links open this app at `/aza`. Without one,
    ///     signing in signs in as the sample account.
    ///   - scopes: What the app asks the aza app for: `sign-in`, and `read` and `write` for sync data.
    ///   - showsSignIn: False for a scene other than the main window, such as Settings or a menu bar extra.
    func azaUI(name: String, icon: String = "Icon", accent: String = Accent.standard,
               appearance: Appearance = .system, appID: String? = nil, scopes: [String] = ["sign-in"],
               showsSignIn: Bool = true) -> some View {
        modifier(Root(info: AppInfo(name: name, icon: icon, accent: accent, appearance: appearance,
                                    appID: appID, scopes: scopes), showsSignIn: showsSignIn))
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
        // Before anything shows, so a cold launch from the aza app's answer finds it configured.
        Account.shared.configure(appID: info.appID, scopes: info.scopes)
    }

    func body(content: Content) -> some View {
        content
            .modifier(Shared(info: info, accent: accent, account: account))
            .onChange(of: appearance, initial: true) { appearance.apply() }
            .onOpenURL { url in if showsSignIn { account.receive(url) } }
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
