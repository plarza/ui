import SwiftUI

extension Chat {
    /// The conversation: your messages in bubbles on the right, the assistant's turns full width,
    /// a date over each new day, and the turn being written at the end. The turn being written has
    /// the ID of the message it'll be stored as and is drawn by the same view, so when that message
    /// arrives it takes the turn's place without anything moving.
    ///
    /// It stays at the bottom while you're there, as text comes in, a turn folds or the keyboard
    /// moves. Scroll up to read and it stays put, with a button back down; sending brings you back.
    /// The latest messages show, and earlier ones a page at a time from the top: every row is laid
    /// out, so the scroll view always knows how tall it is.
    public struct Transcript<Empty: View>: View {
        var messages: [Message]
        var turn: Turn?
        var retry: (Message) -> Void
        var empty: Empty

        @State private var position = ScrollPosition(edge: .bottom)
        /// Following the bottom.
        @State private var pinned = true
        @State private var phase = ScrollPhase.idle
        @State private var limit = Self.page

        private static var page: Int { 40 }

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

        private struct Row: Identifiable {
            var id: String
            var date: Date
            var message: Message?
            var turn: Turn?
            var yours: Bool { message?.author == .you }
        }

        private var rows: [Row] {
            var rows = messages.map { Row(id: $0.id, date: $0.date, message: $0) }
            if let turn, !messages.contains(where: { $0.id == turn.id }) {
                rows.append(Row(id: turn.id, date: turn.started, turn: turn))
            }
            return rows
        }

        /// Where the scroll view is, for keeping to the bottom.
        private struct Metrics: Equatable {
            var content: CGFloat
            var container: CGFloat
            /// How far the bottom of the content is below the bottom of what's visible.
            var below: CGFloat
        }

        public var body: some View {
            let all = rows
            let shown = all.suffix(limit)
            let days = Self.days(all)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if all.isEmpty {
                        empty.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    if all.count > shown.count, let first = shown.first {
                        Button("Earlier messages") { showEarlier(keeping: first.id) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .accessibilityIdentifier("earlier")
                    }
                    ForEach(shown) { row in
                        VStack(alignment: .leading, spacing: 18) {
                            if days.contains(row.id) {
                                DayStamp(date: row.date)
                            }
                            if row.yours, let m = row.message {
                                YourMessage(message: m, retry: retry)
                            } else {
                                AssistantRow(message: row.message, turn: row.turn)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, new in phase = new }
            .onScrollGeometryChange(for: Metrics.self) { g in
                Metrics(content: g.contentSize.height, container: g.containerSize.height,
                        below: g.contentSize.height + g.contentInsets.bottom - g.containerSize.height - g.contentOffset.y)
            } action: { old, new in
                keep(old, new)
            }
            .onChange(of: messages.last?.id) {
                guard messages.last?.author == .you else { return }
                pinned = true
                withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
            }
            .overlay(alignment: .bottom) {
                if !pinned {
                    Button("Latest", systemImage: "arrow.down") {
                        pinned = true
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
            .animation(.snappy, value: pinned)
        }

        /// The rows that start a new day.
        private static func days(_ rows: [Row]) -> Set<String> {
            var days = Set<String>()
            for (i, row) in rows.enumerated() where i == 0 || !Calendar.current.isDate(row.date, inSameDayAs: rows[i - 1].date) {
                days.insert(row.id)
            }
            return days
        }

        /// While you scroll, you're following the bottom only if you're at it. Otherwise, whenever
        /// the content or the space for it changes size while following, it goes back to the
        /// bottom, and it never rests past the end, where there's nothing to see.
        private func keep(_ old: Metrics, _ new: Metrics) {
            switch phase {
            case .tracking, .interacting, .decelerating:
                pinned = new.below < 40
                return
            case .animating:
                return
            default:
                break
            }
            let resized = old.content != new.content || old.container != new.container
            if (pinned && (resized || new.below > 1)) || new.below < -1 {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { position.scrollTo(edge: .bottom) }
            } else if new.below < 40 {
                pinned = true
            }
        }

        private func showEarlier(keeping id: String) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                limit += Self.page
                position.scrollTo(id: id, anchor: .top)
            }
        }
    }

    /// An assistant's message, or the turn being written that it'll become: the one view for both,
    /// so the handover keeps the row as it is. Reads `Turn` here, so only this row redraws as it
    /// streams.
    struct AssistantRow: View {
        var message: Message?
        var turn: Turn?

        var body: some View {
            TurnView(
                parts: turn?.parts ?? message?.parts ?? [],
                text: message?.text ?? "",
                label: message?.label,
                worked: turn.map(\.worked) ?? message?.worked,
                live: turn.map { .init(started: $0.started, going: !$0.ended, writing: $0.isActive) })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(turn == nil ? "message" : "reply")
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
                    .opacity(message.state == .sending ? 0.6 : 1)
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
