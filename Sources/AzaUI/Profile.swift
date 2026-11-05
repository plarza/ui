import SwiftUI

/// The first row of the app's profile page, like Apple Account in Settings. Signed in, it opens the account page;
/// signed out, it signs in. Place it inside the page's `NavigationStack`.
public struct AccountRow: View {
    @Environment(Account.self) private var account
    @Environment(\.accent) private var accent
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        Group {
            if let profile = account.profile {
                NavigationLink { AccountPage() } label: {
                    AccountChip(profile: profile, interactive: true) {
                        if profile.isSample { PreviewLabel() }
                    }
                }
            } else {
                Button { Task { await account.signIn(open: openURL) } } label: {
                    HStack(spacing: 12) {
                        AzaLogo()
                            .fill(accent, style: FillStyle(eoFill: true))
                            .frame(width: 28, height: 28)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(accent.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in with aza").font(.system(size: 20, weight: .bold, design: .rounded))
                            Text(account.waiting ? "Waiting for the aza app" : "Not signed in")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .contentShape(.capsule)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account")
        .sensoryFeedback(.success, trigger: account.profile != nil) { _, signedIn in signedIn }
        .signInProblems()
    }
}

/// Marks the sample account, so it never passes for a real one.
struct PreviewLabel: View {
    var body: some View {
        Text("Preview")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("preview")
    }
}

/// Who you're signed in as, and signing out.
struct AccountPage: View {
    @Environment(Account.self) private var account
    @Environment(\.openURL) private var openURL
    @Environment(\.appInfo) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let profile = account.profile {
                    AccountChip(profile: profile, interactive: false) {
                        if profile.isSample { PreviewLabel() }
                    }
                    .textSelection(.enabled)
                    .padding(.top, 12)
                }
                VStack(spacing: 0) {
                    #if os(iOS)
                    if !(account.profile?.isSample ?? true) {
                        Button { openURL(URL(string: "aza:")!) } label: {
                            HStack {
                                Text("Devices and apps")
                                Spacer()
                                Text("In the aza app").foregroundStyle(.secondary)
                                Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 50)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("openAza")
                        Divider().opacity(0.5)
                    }
                    #endif
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
                    ForEach(Appearance.choices) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
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
