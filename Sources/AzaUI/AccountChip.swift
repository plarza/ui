import SwiftUI

/// An aza account in one element, the same in every app and in the aza app: the picture, the name, then the handle
/// and the start of the account's ID, with the aza mark pressed into the glass behind them on the right. The ID can't be faked, so it's how
/// you tell your account from one with the same name and picture.
public struct AccountChip<Trailing: View>: View {
    let name: String
    let handle: String?
    let identity: String?
    let picture: Image?
    let interactive: Bool
    var sample = false
    let trailing: Trailing

    /// - Parameters:
    ///   - identity: The account's ID as hex. Its first 16 characters are shown in groups of four.
    ///   - picture: Nil shows the name's initials on the app's colour.
    ///   - interactive: True when it's a button or link, so it answers a press.
    ///   - trailing: Anything after the text, such as a chevron.
    public init(name: String, handle: String? = nil, identity: String?, picture: Image?, interactive: Bool = false,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.name = name
        self.handle = handle
        self.identity = identity
        self.picture = picture
        self.interactive = interactive
        self.trailing = trailing()
    }

    /// The signed-in account of this app, as `AccountRow` shows it.
    init(profile: Profile, interactive: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.init(name: profile.name, handle: profile.handle, identity: profile.identity,
                  picture: profile.isSample ? nil : profile.image, interactive: interactive, trailing: trailing)
        sample = profile.isSample
    }

    public var body: some View {
        HStack(spacing: 12) {
            AccountPicture(name: name, picture: picture, size: 52, sample: sample)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if handle != nil || identity != nil {
                    Self.detail(handle: handle, identity: identity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 10)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(alignment: .trailing) { EngravedMark().frame(width: 120, height: 120).offset(x: 22) }
        .clipShape(.capsule)
        .contentShape(.capsule)
        .glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
    }

    /// The handle as written, then the start of the ID in fixed-width digits.
    public static func detail(handle: String?, identity: String?) -> Text {
        let id = identity.map { Text(shortID($0)).monospaced() }
        switch (handle, id) {
        case let (handle?, id?): return Text("\(handle) · \(id)")
        case let (handle?, nil): return Text(handle)
        case let (nil, id?): return id
        case (nil, nil): return Text("")
        }
    }

    /// The first 16 characters of an ID, in groups of four: `9557 a8a8 b00e d7ed`.
    public static func shortID(_ id: String) -> String {
        let start = Array(id.prefix(16))
        return stride(from: 0, to: start.count, by: 4).map { String(start[$0..<min($0 + 4, start.count)]) }
            .joined(separator: " ")
    }
}

/// The aza mark pressed into the glass: a dark cut with a light edge just below it.
struct EngravedMark: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AzaLogo().fill(.white.opacity(scheme == .dark ? 0.12 : 0.9), style: FillStyle(eoFill: true)).offset(y: 1.5)
            AzaLogo().fill(.black.opacity(scheme == .dark ? 0.45 : 0.1), style: FillStyle(eoFill: true))
        }
        // Mirrored, so the part left showing at the chip's edge reads as the a.
        .scaleEffect(x: -1)
        .accessibilityHidden(true)
    }
}

/// A picture in a circle; without one, the name's initials on the app's colour, as `ProfileButton` shows it. The
/// sample account is a grey person, so it never passes for a real one.
struct AccountPicture: View {
    let name: String
    let picture: Image?
    let size: CGFloat
    var sample = false
    @Environment(\.accent) private var accent
    @Environment(\.onAccent) private var onAccent

    var body: some View {
        Group {
            if sample {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Circle().fill(.quaternary))
            } else if let picture {
                picture.resizable().scaledToFill()
            } else {
                Text(Profile(name: name).initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Circle().fill(accent.gradient))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Saved pictures, read from disk once.
@MainActor private var pictures: [URL: Image] = [:]

extension Profile {
    /// The saved picture, read from its file once.
    var image: Image? {
        guard let picture, picture.isFileURL else { return nil }
        if let cached = pictures[picture] { return cached }
        guard let data = try? Data(contentsOf: picture) else { return nil }
        #if os(macOS)
        let image = NSImage(data: data).map(Image.init(nsImage:))
        #else
        let image = UIImage(data: data).map(Image.init(uiImage:))
        #endif
        pictures[picture] = image
        return image
    }
}
