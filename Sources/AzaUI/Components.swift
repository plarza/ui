import SwiftUI

/// The system background with a soft glow of the app's colour from the top.
public struct Backdrop: View {
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        ZStack {
            #if os(iOS)
            Color(.systemBackground)
            #else
            Color(.windowBackgroundColor)
            #endif
            RadialGradient(colors: [accent.opacity(scheme == .dark ? 0.22 : 0.12), .clear],
                           center: UnitPoint(x: 0.2, y: -0.05), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: accent)
    }
}

/// Full-width button in the app's colour for a screen's main action.
public struct PrimaryButton<Label: View>: View {
    var large: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.accent) private var accent
    @Environment(\.onAccent) private var onAccent

    public init(large: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.large = large
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(action: action) {
            label
                .font(large ? .title2.weight(.semibold) : .title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: large ? 50 : 44)
        }
        .buttonStyle(.glassProminent)
        .tint(accent)
        .foregroundStyle(onAccent)
    }
}

public extension PrimaryButton where Label == Text {
    init(_ title: String, large: Bool = false, action: @escaping () -> Void) {
        self.init(large: large, action: action) { Text(title) }
    }
}

/// Full-width plain glass button for secondary actions.
public struct GlassButton: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .tint(.primary)
    }
}

/// A round Liquid Glass button with a symbol. `on` fills it with the app's colour.
public struct CircleButton: View {
    let symbol: String
    let label: String
    var size: CGFloat
    var symbolSize: CGFloat?
    var on: Bool
    let action: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.onAccent) private var onAccent

    /// - Parameters:
    ///   - label: Read by VoiceOver; also the accessibility identifier unless the view sets its own.
    ///   - symbolSize: Defaults to 39% of `size`.
    public init(_ symbol: String, label: String, size: CGFloat = 48, symbolSize: CGFloat? = nil, on: Bool = false,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.size = size
        self.symbolSize = symbolSize
        self.on = on
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize ?? size * 0.39, weight: .semibold))
                .foregroundStyle(on ? onAccent : accent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(accent).interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: on)
    }
}

/// A glass card that groups rows, the building block of every settings-like page.
public struct Card<Content: View>: View {
    var padding: CGFloat
    @ViewBuilder let content: Content

    /// - Parameter padding: Vertical padding; rows that bring their own height (FormRow) want none.
    public init(padding: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// A section title above a card.
public struct Heading: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .padding(.leading, 4)
            .padding(.top, 20)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Label on the left, control on the right, divider below.
public struct FormRow<Content: View>: View {
    let label: String
    var last: Bool
    @ViewBuilder let content: Content

    public init(_ label: String, last: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.last = last
        self.content = content()
    }

    public var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            content
        }
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) { if !last { Divider().opacity(0.5) } }
    }
}

/// A value in the app's colour that you tap to change.
public struct Token: View {
    let text: String
    let action: () -> Void
    @Environment(\.accent) private var accent

    public init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.18)))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
    }
}

/// A short message in a glass capsule.
public struct Toast: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
    }
}

public extension View {
    /// Shows `message` at the top for a couple of seconds, then clears it.
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                Toast(text)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(.smooth) { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: message.wrappedValue)
    }
}

/// Dips slightly when pressed, like system controls.
public struct PressableStyle: ButtonStyle {
    var scale: CGFloat

    public init(scale: CGFloat = 0.94) { self.scale = scale }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
