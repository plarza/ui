import SwiftUI

/// The aza mark filled with the current foreground style.
public struct AzaMark: View {
    public init() {}

    public var body: some View {
        AzaLogo()
            .fill(.foreground, style: FillStyle(eoFill: true))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// Full screen on first launch: the app's icon and name, then sign in with aza or skip.
public struct SignInScreen: View {
    @Environment(AzaAccount.self) private var account
    @Environment(\.azaApp) private var app
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(app.icon)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 112)
                .clipShape(.rect(cornerRadius: 26))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .accessibilityHidden(true)
            Text(app.name)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .padding(.top, 20)
            Spacer()
            Spacer()
            SignInButton()
            Button("Skip") { withAnimation(.smooth) { account.skip() } }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(.rect)
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("aza.skip")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(Backdrop())
        .interactiveDismissDisabled()
        .sensoryFeedback(.success, trigger: account.signedIn) { _, signedIn in signedIn }
    }
}

/// "Sign in with aza", full width in the app's colour.
public struct SignInButton: View {
    @Environment(AzaAccount.self) private var account
    var large: Bool

    public init(large: Bool = true) { self.large = large }

    public var body: some View {
        PrimaryButton(large: large) {
            withAnimation(.smooth) { account.signIn() }
        } label: {
            HStack(spacing: 10) {
                AzaMark().frame(width: large ? 26 : 22)
                Text("Sign in with aza")
            }
        }
        .accessibilityIdentifier("aza.signIn")
    }
}

/// An aza profile picture, or initials on the app's colour when there isn't one (or it hasn't loaded).
public struct ProfilePicture: View {
    let profile: AzaProfile?
    var size: CGFloat
    @Environment(\.accent) private var accent
    @Environment(\.onAccent) private var onAccent

    public init(_ profile: AzaProfile?, size: CGFloat) {
        self.profile = profile
        self.size = size
    }

    public var body: some View {
        AsyncImage(url: profile?.picture, transaction: Transaction(animation: .smooth)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(LinearGradient(colors: [accent.opacity(0.75), accent], startPoint: .top, endPoint: .bottom))
                    if let initials = profile?.initials, !initials.isEmpty {
                        Text(initials).font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    } else {
                        Image(systemName: "person.fill").font(.system(size: size * 0.45, weight: .semibold))
                    }
                }
                .foregroundStyle(onAccent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Top right of the app's main screen; opens Profile. Your aza picture in a glass ring when signed in,
/// a glass person button in the app's colour when not.
public struct ProfileButton: View {
    @Environment(AzaAccount.self) private var account
    var size: CGFloat
    let action: () -> Void

    public init(size: CGFloat = 48, action: @escaping () -> Void) {
        self.size = size
        self.action = action
    }

    public var body: some View {
        Group {
            if let profile = account.profile {
                Button(action: action) {
                    ProfilePicture(profile, size: size - 6)
                        .padding(3)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .transition(.blurReplace)
            } else {
                CircleButton("person.crop.circle", label: "Profile", size: size, symbolSize: size * 0.5, action: action)
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: account.signedIn)
        .accessibilityLabel("Profile")
        .accessibilityIdentifier("profile")
    }
}
