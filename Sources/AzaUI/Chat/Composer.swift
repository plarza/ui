import SwiftUI

extension Chat {
    /// Where you write. It grows to six lines; while the assistant answers, send turns into stop and
    /// you can keep writing the next message. With a hardware keyboard, Return sends and
    /// Shift-Return starts a new line. Keep `text` in `@AppStorage` so a draft survives the app
    /// closing.
    public struct Composer: View {
        @Binding var text: String
        var answering: Bool
        var placeholder: String
        var send: (String) -> Void
        var stop: () -> Void

        @Environment(\.accent) private var accent
        @Environment(\.onAccent) private var onAccent
        @FocusState private var focused: Bool
        @State private var sent = 0

        public init(text: Binding<String>, answering: Bool, placeholder: String = "Message",
                    send: @escaping (String) -> Void, stop: @escaping () -> Void) {
            _text = text
            self.answering = answering
            self.placeholder = placeholder
            self.send = send
            self.stop = stop
        }

        private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

        public var body: some View {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        guard !press.modifiers.contains(.shift) else { return .ignored }
                        submit()
                        return .handled
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    .accessibilityIdentifier("chatField")
                button
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .sensoryFeedback(.impact(weight: .light), trigger: sent)
        }

        private var button: some View {
            Button {
                if answering { stop() } else { submit() }
            } label: {
                Image(systemName: answering ? "stop.fill" : "arrow.up")
                    .font(.system(size: answering ? 14 : 17, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(onAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(accent))
            }
            .buttonStyle(.plain)
            .disabled(!answering && trimmed.isEmpty)
            .opacity(!answering && trimmed.isEmpty ? 0.4 : 1)
            .animation(.snappy, value: answering)
            .accessibilityLabel(answering ? "Stop" : "Send")
            .accessibilityIdentifier(answering ? "stop" : "send")
        }

        private func submit() {
            let message = trimmed
            guard !message.isEmpty, !answering else { return }
            text = ""
            sent += 1
            send(message)
        }
    }
}
