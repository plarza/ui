import SwiftUI

/// The page behind the profile button: your aza account at the top, the app's own sections, then Appearance.
/// Push the app's own pages with `NavigationLink(value:)` and `.navigationDestination` inside `content`.
public struct ProfilePage<Content: View>: View {
    private let external: Binding<NavigationPath>?
    @State private var own = NavigationPath()
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    public init(path: Binding<NavigationPath>? = nil, @ViewBuilder content: () -> Content) {
        external = path
        self.content = content()
    }

    public var body: some View {
        NavigationStack(path: external ?? $own) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AccountRow()
                    content
                    Heading("Appearance")
                    AppearanceSection()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Backdrop())
            .navigationTitle("Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: AzaRoute.self) { _ in AccountView() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("profile.done")
                }
            }
        }
    }
}

enum AzaRoute: Hashable { case account }

/// The first row of Profile, like Apple Account in Settings: opens the account page, or signs in.
public struct AccountRow: View {
    @Environment(AzaAccount.self) private var account
    @Environment(\.accent) private var accent

    public init() {}

    public var body: some View {
        Group {
            if let profile = account.profile {
                NavigationLink(value: AzaRoute.account) {
                    row(title: profile.name, subtitle: [profile.handle.map { "@\($0)" }, "aza account"].compactMap(\.self).joined(separator: " · ")) {
                        ProfilePicture(profile, size: 56)
                    }
                }
            } else {
                Button { withAnimation(.smooth) { account.signIn() } } label: {
                    row(title: "Sign in with aza", subtitle: "Not signed in") {
                        AzaMark()
                            .foregroundStyle(accent)
                            .frame(width: 34)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(accent.opacity(0.15)))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .padding(.top, 8)
        .accessibilityIdentifier("profile.account")
        .sensoryFeedback(.success, trigger: account.signedIn) { _, signedIn in signedIn }
    }

    private func row(title: String, subtitle: String, @ViewBuilder picture: () -> some View) -> some View {
        HStack(spacing: 14) {
            picture()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.bold)).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

/// Your aza account: who you're signed in as here, and signing out.
struct AccountView: View {
    @Environment(AzaAccount.self) private var account
    @Environment(\.azaApp) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let profile = account.profile {
                    ProfilePicture(profile, size: 104).padding(.top, 12)
                    Text(profile.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    if let handle = profile.handle {
                        HStack(spacing: 5) {
                            AzaMark().frame(width: 14)
                            Text("@\(handle)")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
                Card {
                    FormRow("Devices and apps") {
                        Text("In the aza app").foregroundStyle(.tertiary)
                    }
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        Text("Sign out of \(app.name)")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aza.signOut")
                }
                .padding(.top, 12)
                Text("Signing out keeps everything in \(app.name) on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
        }
        .background(Backdrop())
        .navigationTitle("aza account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Sign out of \(app.name)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                account.signOut()
                dismiss()
            }
        }
    }
}

/// Theme and colour, the same in every app.
public struct AppearanceSection: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    @AppStorage(Accent.key) private var accent = Accent.standard
    @Environment(\.azaApp) private var app
    @Namespace private var ring

    public init() {}

    public var body: some View {
        Card {
            FormRow("Theme") {
                Picker("Theme", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityIdentifier("appearance.theme")
            }
            HStack(spacing: 0) {
                ForEach(Accent.presets, id: \.self) { hex in
                    Button { withAnimation(.spring(duration: 0.4, bounce: 0.3)) { accent = hex } } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .padding(4)
                            .overlay {
                                if accent == hex {
                                    Circle().stroke(.primary, lineWidth: 2).matchedGeometryEffect(id: "ring", in: ring)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Self.name(hex))
                    .accessibilityAddTraits(accent == hex ? .isSelected : [])
                    .accessibilityIdentifier("accent.\(hex)")
                }
                ColorPicker("Custom colour", selection: Binding(get: { Color(hex: accent) }, set: { accent = $0.hex }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
        }
        .sensoryFeedback(.selection, trigger: appearance)
        .sensoryFeedback(.selection, trigger: accent)
        .onAppear {
            // AppStorage's default is fixed at compile time; the app's own default lives in AzaApp.
            if UserDefaults.standard.string(forKey: Accent.key) == nil { accent = app.accent }
            if UserDefaults.standard.string(forKey: Appearance.key) == nil { appearance = app.appearance }
        }
    }

    private static func name(_ hex: String) -> String {
        switch hex {
        case Accent.standard: "Black and white"
        case "FF375F": "Pink"
        case "FF9F0A": "Orange"
        case "30D158": "Green"
        case "0A84FF": "Blue"
        case "5E5CE6": "Indigo"
        default: "Colour"
        }
    }
}
