import AzaKit
import Foundation
import Observation
import Security
import SwiftUI

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

    /// Stands in for a real identity in apps without an aza app ID, and in UI tests. Plainly not a real account.
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
/// Signing in asks the aza app for a certificate (protocol section 7): it opens `aza:approve#req=…`, and the aza
/// app answers by opening `https://<app ID>/aza#aza=…`, a universal link back to this app, which `.azaUI` hands to
/// `receive`. The client's keys and certificate stay in the Keychain on this device. An app without an app ID signs
/// in as `Profile.sample` instead.
@Observable
public final class Account {
    public static let shared = Account()

    public private(set) var profile: Profile?
    /// Signed in or skipped.
    public private(set) var answered: Bool
    /// This app's aza client once signed in: sync data (`readAll`, `write`) and proving who's signed in to the app's
    /// own server (`signIn`).
    public private(set) var client: AzaClient?
    /// Sent to the aza app; its answer hasn't come back yet.
    public private(set) var waiting = false
    /// Why signing in last failed, shown by the screen that started it.
    public var problem: SignInProblem?
    /// On a Mac, the QR code to scan with the aza app on a phone while signing in.
    public private(set) var qr: String?

    private var appID: String?
    private var scopes = ["sign-in"]
    private var pending: AzaClient?
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
        let client = saved == nil ? nil : Keychain.read("client").flatMap { try? AzaClient.load(saved: $0) }
        self.client = client
        profile = saved?.isSample == true || client != nil ? saved : nil
        answered = defaults.bool(forKey: Self.answeredKey) || saved != nil
        if let client { Task { await refresh(client) } }
    }

    /// Set by `.azaUI`. A sample account from before the app had an app ID is signed out.
    func configure(appID: String?, scopes: [String]) {
        self.appID = appID
        self.scopes = scopes
        if appID != nil, profile?.isSample == true, ProcessInfo.processInfo.environment["SAMPLE_ACCOUNT"] != "1" {
            profile = nil
            save()
        }
    }

    /// Asks the aza app to approve this app, through `open` (the view's `openURL`).
    public func signIn(open: OpenURLAction) async {
        guard let appID else {
            profile = .sample
            answered = true
            save()
            return
        }
        do {
            let client = try AzaClient(app: appID, scopes: scopes, returnUrl: "https://\(appID)/aza")
            #if os(macOS)
            try await signInFromPhone(client, appID: appID)
            #else
            try await signInHere(client, open: open)
            #endif
        } catch {
            problem = .failed(error.localizedDescription)
        }
    }

    /// The same-machine path: the aza app on this device approves.
    private func signInHere(_ client: AzaClient, open: OpenURLAction) async throws {
        guard let url = client.approveUrl().flatMap(URL.init(string:)) else { return }
        // iOS may end this app while the aza app is open, so the waiting client is kept where it can come back.
        Keychain.write("pending", await client.save())
        pending = client
        waiting = true
        open(url) { [self] opened in
            if !opened {
                waiting = false
                problem = .noAzaApp
            }
        }
    }

    #if os(macOS)
    /// A Mac has no aza app, so it signs in from the phone's (protocol section 7, from another machine). The
    /// app's server hosts the request: `POST https://<app ID>/aza/request` with `{"approve": "aza:approve#req=…"}`
    /// answers `{"qr": …}`. The aza app scans the QR code, fetches the request from the server and posts the
    /// certificate to the return URL; the Mac collects it from `GET https://<app ID>/aza/certificate/<client
    /// fingerprint>`, which answers 204 until then and `{"url": "https://<app ID>/aza#aza=…"}` after.
    private func signInFromPhone(_ client: AzaClient, appID: String) async throws {
        guard let approve = client.approveUrl() else { return }
        let base = URL(string: "https://\(appID)/aza")!
        var post = URLRequest(url: base.appending(path: "request"))
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.httpBody = try JSONEncoder().encode(["approve": approve])
        let (data, response) = try await URLSession.shared.data(for: post)
        struct Hosted: Decodable { var qr: String }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SignInError.server }
        pending = client
        qr = try JSONDecoder().decode(Hosted.self, from: data).qr
        waiting = true
        defer { if self.pending === client { qr = nil; waiting = false; pending = nil } }
        let poll = base.appending(path: "certificate/\(await client.fingerprint())")
        let until = Date.now.addingTimeInterval(10 * 60)
        while waiting, pending === client, Date.now < until {
            if let (data, response) = try? await URLSession.shared.data(from: poll),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                struct Answer: Decodable { var url: URL }
                let answer = try JSONDecoder().decode(Answer.self, from: data)
                qr = nil
                await finish(answer.url)
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private enum SignInError: LocalizedError {
        case server
        var errorDescription: String? { "The app's server didn't answer. Try again in a moment." }
    }
    #endif

    /// Stops waiting for the aza app.
    public func cancelSignIn() {
        waiting = false
        qr = nil
        pending = nil
    }

    /// Takes the aza app's answer, `https://<app ID>/aza#aza=…`. False for any other URL.
    @discardableResult
    public func receive(_ url: URL) -> Bool {
        guard let appID, url.scheme == "https", url.host() == appID, url.path() == "/aza",
              url.fragment()?.hasPrefix("aza=") == true else { return false }
        Task { await finish(url) }
        return true
    }

    private func finish(_ url: URL) async {
        defer { waiting = false }
        do {
            guard let client = try pending ?? Keychain.read("pending").map({ try AzaClient.load(saved: $0) }) else {
                return
            }
            try await client.receive(url: url.absoluteString)
            Keychain.write("client", await client.save())
            Keychain.delete("pending")
            pending = nil
            self.client = client
            profile = (try? await Self.profile(of: client)) ?? Profile(name: "aza account")
            answered = true
            save()
        } catch {
            problem = .failed(error.localizedDescription)
        }
    }

    /// The name, picture or handle may have changed in the aza app since.
    private func refresh(_ client: AzaClient) async {
        guard let fresh = try? await Self.profile(of: client), self.client === client else { return }
        profile = fresh
        save()
    }

    private static func profile(of client: AzaClient) async throws -> Profile {
        let info = try await client.profile()
        var picture: URL?
        if let hash = info.pictureHash, let image = try await client.picture() {
            let file = URL.cachesDirectory.appending(path: "aza-picture-\(hash)")
            try image.write(to: file)
            picture = file
        }
        return Profile(name: info.name ?? "aza account", picture: picture, handle: info.handle)
    }

    public func skip() {
        answered = true
        save()
    }

    /// Forgets this app's client. Revoking it, so it can never be used again, is done in the aza app.
    public func signOut() {
        if let picture = profile?.picture, picture.isFileURL { try? FileManager.default.removeItem(at: picture) }
        Keychain.delete("client")
        client = nil
        profile = nil
        save()
    }

    private func save() {
        defaults.set(answered, forKey: Self.answeredKey)
        defaults.set(profile.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.profileKey)
    }
}

/// Why signing in didn't work.
public enum SignInProblem: Equatable, Sendable {
    /// Nothing opens `aza:` links on this device.
    case noAzaApp
    case failed(String)

    var title: String {
        switch self {
        case .noAzaApp: "Get the aza app"
        case .failed: "Couldn't sign in"
        }
    }

    var message: String {
        switch self {
        case .noAzaApp: "Signing in with aza needs the aza app on this device. It keeps your account and approves sign-ins."
        case .failed(let reason): reason
        }
    }
}

/// The client's saved keys and certificate, for this app and device only.
enum Keychain {
    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "aza", kSecAttrAccount as String: name]
    }

    static func read(_ name: String) -> Data? {
        var result: AnyObject?
        var q = query(name)
        q[kSecReturnData as String] = true
        return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }

    static func write(_ name: String, _ data: Data) {
        delete(name)
        var q = query(name)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ name: String) {
        SecItemDelete(query(name) as CFDictionary)
    }
}
