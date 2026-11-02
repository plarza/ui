import SwiftUI

extension Chat {
    /// The conversation: your messages in bubbles on the right, the assistant's turns full width,
    /// a date over each new day, and the turn being written at the end. The turn being written has
    /// the ID of the message it'll be stored as, so when that message arrives it takes the turn's
    /// place without anything moving. The view follows new text only while you're at the bottom;
    /// scroll up to read and it stays put, with a button back down. Sending brings you back.
    public struct Transcript<Empty: View>: View {
        var messages: [Message]
        var turn: Turn?
        var retry: (Message) -> Void
        var empty: Empty

        @State private var position = ScrollPosition(edge: .bottom)
        @State private var atBottom = true
        @State private var touching = false

        /// - Parameters:
        ///   - turn: The assistant's turn being written, if any. Leave it out once `messages` has
        ///     its message.
        ///   - retry: Sends a failed message again.
        ///   - empty: Shown while there are no messages.
        public init(messages: [Message], turn: Turn?, retry: @escaping (Message) -> Void = { _ in },
                    @ViewBuilder empty: () -> Empty) {
            self.messages = messages
            self.turn = turn
            self.retry = retry
            self.empty = empty()
        }

        private enum Row: Identifiable {
            case message(Message)
            case turn(Turn)

            var id: String {
                switch self {
                case .message(let m): m.id
                case .turn(let t): t.id
                }
            }

            var date: Date {
                switch self {
                case .message(let m): m.date
                case .turn(let t): t.started
                }
            }
        }

        private var rows: [Row] {
            var rows = messages.map(Row.message)
            if let turn, !messages.contains(where: { $0.id == turn.id }) { rows.append(.turn(turn)) }
            return rows
        }

        public var body: some View {
            let rows = rows
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if rows.isEmpty {
                        empty.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        VStack(alignment: .leading, spacing: 18) {
                            if i == 0 || !Calendar.current.isDate(row.date, inSameDayAs: rows[i - 1].date) {
                                DayStamp(date: row.date)
                            }
                            switch row {
                            case .message(let m) where m.author == .you:
                                YourMessage(message: m, retry: retry)
                            case .message(let m):
                                TurnView(parts: m.parts, text: m.text, label: m.label, worked: m.worked)
                            case .turn(let t):
                                LiveTurn(turn: t)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { g in
                // `containerSize` is the visible area inside the insets.
                g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 40
            } action: { _, bottom in
                atBottom = bottom
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in follow() }
            .onScrollPhaseChange { _, phase in touching = phase == .interacting }
            .onChange(of: messages.last?.id) {
                if messages.last?.author == .you {
                    withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
                    atBottom = true
                }
            }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button("Latest", systemImage: "arrow.down") {
                        withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(.bottom, 10)
                    .transition(.scale(0.6).combined(with: .opacity))
                    .accessibilityIdentifier("latest")
                }
            }
            .animation(.snappy, value: atBottom)
        }

        /// Keeps the newest text in view as it grows, unless you've scrolled away or have a finger on
        /// it.
        private func follow() {
            guard atBottom, !touching, turn != nil else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { position.scrollTo(edge: .bottom) }
        }
    }

    /// The turn being written, read from `Turn` so only this row redraws as it streams.
    struct LiveTurn: View {
        let turn: Turn

        var body: some View {
            TurnView(parts: turn.parts, text: "", worked: turn.ended ? .seconds(Date.now.timeIntervalSince(turn.started)) : nil,
                     live: (turn.started, !turn.ended))
                .accessibilityIdentifier("reply")
        }
    }

    struct DayStamp: View {
        let date: Date

        var body: some View {
            Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    struct YourMessage: View {
        let message: Message
        let retry: (Message) -> Void

        var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.primary.opacity(0.08), in: .rect(cornerRadius: 20))
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(message.text) }
                    }
                if case .failed(let why) = message.state {
                    Button { retry(message) } label: {
                        Label("\(why). Tap to retry.", systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("retry")
                }
            }
            .frame(maxWidth: 320, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        }
    }
}
