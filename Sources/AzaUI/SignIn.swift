import SwiftUI

/// Full screen on first launch: the app's icon and name, then sign in with aza or skip.
struct SignInScreen: View {
    @Environment(Account.self) private var account
    @Environment(\.appInfo) private var app
    @Environment(\.accent) private var accent
    @Environment(\.onAccent) private var onAccent
    @Environment(\.openURL) private var openURL

    var body: some View {
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
                .padding(.top, 20)
            Spacer()
            Spacer()
            Button { Task { await account.signIn(open: openURL) } } label: {
                HStack(spacing: 10) {
                    if account.waiting {
                        ProgressView().tint(onAccent)
                    } else {
                        AzaLogo()
                            .fill(.foreground, style: FillStyle(eoFill: true))
                            .frame(width: 26, height: 26)
                    }
                    Text(account.waiting ? "Waiting for aza" : "Sign in with aza")
                }
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(onAccent)
            .accessibilityIdentifier("signIn")
            Button("Skip") { withAnimation(.smooth) { account.skip() } }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(.rect)
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("skip")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .interactiveDismissDisabled()
        .signInProblems()
    }
}

extension View {
    /// Shows why signing in failed.
    func signInProblems() -> some View {
        modifier(SignInProblems())
    }
}

private struct SignInProblems: ViewModifier {
    @Environment(Account.self) private var account

    func body(content: Content) -> some View {
        content.alert(account.problem?.title ?? "", isPresented: Binding(
            get: { account.problem != nil },
            set: { if !$0 { account.problem = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(account.problem?.message ?? "")
        }
    }
}

/// A profile picture, or initials on the app's colour when there isn't one or it hasn't loaded.
/// The sample account is a grey person, so it never passes for a real one.
struct ProfilePicture: View {
    let profile: Profile?
    let size: CGFloat
    @Environment(\.accent) private var accent
    @Environment(\.onAccent) private var onAccent

    var body: some View {
        if profile?.isSample == true {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(.quaternary))
                .accessibilityHidden(true)
        } else {
            picture
        }
    }

    private var picture: some View {
        AsyncImage(url: profile?.picture, transaction: Transaction(animation: .smooth)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(accent.gradient)
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

/// Top right of the app's main screen; opens the app's profile page. Signed in, your picture in a glass ring;
/// signed out, a glass person button in the app's colour.
public struct ProfileButton: View {
    @Environment(Account.self) private var account
    @Environment(\.accent) private var accent
    let size: CGFloat
    let action: () -> Void

    public init(size: CGFloat = 48, action: @escaping () -> Void) {
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if let profile = account.profile {
                    ProfilePicture(profile: profile, size: size - 6)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: size, height: size)
            .contentShape(.circle)
            .transition(.blurReplace)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .animation(.smooth, value: account.profile)
        .accessibilityLabel("Profile")
        .accessibilityIdentifier("profile")
    }
}
