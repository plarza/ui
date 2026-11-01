import Foundation
import Observation

/// What other people see of an identity (protocol section 6).
public struct Profile: Codable, Equatable, Sendable {
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

    /// Stands in for a real identity until the aza app can approve sign-ins. Plainly not a real account.
    public static let sample = Profile(name: "Sample account")

    /// The stand-in, shown with a grey picture and a Preview label.
    public var isSample: Bool { self == .sample }

    /// Up to two initials, for when there's no picture.
    var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" }).filter { $0.first?.isLetter == true }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}

/// Who's signed in to this app. The sign-in screen shows on first launch; skipping is remembered.
///
/// Signing in is a stand-in: the aza app that approves sign-ins (protocol section 7) doesn't exist yet,
/// so it signs in as `Profile.sample`.
@Observable
public final class Account {
    public static let shared = Account()

    public private(set) var profile: Profile?
    /// Signed in or skipped.
    public private(set) var answered: Bool

    private let defaults: UserDefaults
    static let profileKey = "account"
    static let answeredKey = "signInAnswered"

    /// UI tests launch with `-signInAnswered YES` to skip the sign-in screen, and `SAMPLE_ACCOUNT=1` to start signed in.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.environment["SAMPLE_ACCOUNT"] == "1" {
            profile = .sample
            answered = true
            return
        }
        let saved = defaults.data(forKey: Self.profileKey).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }
        // Every saved profile is a stand-in until real sign-in exists; earlier builds saved one that looked real.
        profile = saved == nil ? nil : .sample
        answered = defaults.bool(forKey: Self.answeredKey) || saved != nil
    }

    public func signIn() {
        profile = .sample
        answered = true
        save()
    }

    public func skip() {
        answered = true
        save()
    }

    public func signOut() {
        profile = nil
        save()
    }

    private func save() {
        defaults.set(answered, forKey: Self.answeredKey)
        defaults.set(profile.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.profileKey)
    }
}
