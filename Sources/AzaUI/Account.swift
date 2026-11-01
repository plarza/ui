import Foundation
import Observation

/// What other people see of an aza identity (protocol section 6).
public struct AzaProfile: Codable, Equatable, Sendable {
    /// Display name, up to 64 characters. Not unique.
    public var name: String
    /// An https image URL.
    public var picture: URL?
    /// A domain the identity has proved it owns, shown as @handle.
    public var handle: String?

    public init(name: String, picture: URL? = nil, handle: String? = nil) {
        self.name = name
        self.picture = picture
        self.handle = handle
    }

    /// Stands in for a real identity until the aza app can approve sign-ins.
    public static let sample = AzaProfile(name: "aiden", picture: URL(string: "https://github.com/s1dny.png"), handle: "sidny.me")

    /// Up to two initials, for when there's no picture.
    public var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" }).filter { $0.first?.isLetter == true }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}

/// This app's aza sign-in. Every app asks once, on first launch; skipping is remembered and the profile page can
/// sign in later.
///
/// Signing in is a stand-in for now: the aza app that approves sign-ins (protocol section 7) doesn't exist yet,
/// so it signs in as `AzaProfile.sample`.
@Observable
public final class AzaAccount {
    public static let shared = AzaAccount()

    public private(set) var profile: AzaProfile?
    /// Signed in or skipped: either way the sign-in screen has been answered.
    public private(set) var decided: Bool

    public var signedIn: Bool { profile != nil }

    private let defaults: UserDefaults
    private static let profileKey = "aza.profile"
    private static let decidedKey = "aza.decided"

    /// UI tests launch with `-aza.decided YES` to skip the sign-in screen, and `AZA_SIGNED_IN=1` to start signed in.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.environment["AZA_SIGNED_IN"] == "1" {
            profile = .sample
            decided = true
            return
        }
        let saved = defaults.data(forKey: Self.profileKey).flatMap { try? JSONDecoder().decode(AzaProfile.self, from: $0) }
        profile = saved
        decided = defaults.bool(forKey: Self.decidedKey) || saved != nil
    }

    public func signIn() {
        profile = .sample
        decided = true
        save()
    }

    public func skip() {
        decided = true
        save()
    }

    public func signOut() {
        profile = nil
        save()
    }

    private func save() {
        defaults.set(decided, forKey: Self.decidedKey)
        defaults.set(profile.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.profileKey)
    }
}
