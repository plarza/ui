import SwiftUI

/// The first row of the app's profile page, like Apple Account in Settings. Signed in, it opens the account page;
/// signed out, it signs in. Place it inside the page's `NavigationStack`.
public struct AccountRow: View {
    @Environment(Account.self) private var account
    @Environment(\.accent) private var accent

    public init() {}

    public var body: some View {
        Group {
            if let profile = account.profile {
                NavigationLink { AccountPage() } label: {
                    row(profile.name, [profile.handle.map { "@\($0)" }, "aza account"].compactMap(\.self).joined(separator: " · ")) {
                        ProfilePicture(profile: profile, size: 56)
                    }
                }
            } else {
                Button { withAnimation(.smooth) { account.signIn() } } label: {
                    row("Sign in with aza", "Not signed in") {
                        AzaLogo()
                            .fill(accent, style: FillStyle(eoFill: true))
                            .frame(width: 34, height: 34)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(accent.opacity(0.15)))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .accessibilityIdentifier("account")
        .sensoryFeedback(.success, trigger: account.profile != nil) { _, signedIn in signedIn }
    }

    private func row(_ title: String, _ subtitle: String, @ViewBuilder picture: () -> some View) -> some View {
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

/// Who you're signed in as, and signing out.
struct AccountPage: View {
    @Environment(Account.self) private var account
    @Environment(\.appInfo) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let profile = account.profile {
                    ProfilePicture(profile: profile, size: 104).padding(.top, 12)
                    Text(profile.name).font(.system(size: 30, weight: .bold, design: .rounded))
                    if let handle = profile.handle {
                        HStack(spacing: 5) {
                            AzaLogo().fill(.foreground, style: FillStyle(eoFill: true)).frame(width: 14, height: 14)
                            Text("@\(handle)")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("Devices and apps").foregroundStyle(.secondary)
                        Spacer()
                        Text("In the aza app").foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 50)
                    Divider().opacity(0.5)
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        Text("Sign out of \(app.name)")
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("signOut")
                }
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.top, 12)
                Text("Signing out keeps everything in \(app.name) on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Account")
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
    @Environment(\.appInfo) private var app
    @Namespace private var ring

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Theme").foregroundStyle(.secondary)
                Spacer()
                Picker("Theme", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityIdentifier("theme")
            }
            .frame(minHeight: 50)
            Divider().opacity(0.5)
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
                    .accessibilityLabel(Accent.name(hex))
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
        .padding(.horizontal, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .sensoryFeedback(.selection, trigger: appearance)
        .sensoryFeedback(.selection, trigger: accent)
        .onAppear {
            // The AppStorage defaults above are fixed; the app's own defaults come from `.azaUI(...)`.
            if UserDefaults.standard.string(forKey: Accent.key) == nil { accent = app.accent }
            if UserDefaults.standard.string(forKey: Appearance.key) == nil { appearance = app.appearance }
        }
    }
}
