import SwiftUI

extension Chat {
    /// The conversation: your messages in bubbles on the right, the assistant's as full-width
    /// markdown, a date over each new day, and the reply being written at the end. It follows new
    /// text only while you're at the bottom; scroll up to read and it stays put, with a button back
    /// down. Sending always brings you back.
    public struct Transcript<Empty: View>: View {
        var messages: [Message]
        var reply: Reply?
        var retry: (Message) -> Void
        var empty: Empty

        @State private var position = ScrollPosition(edge: .bottom)
        @State private var atBottom = true
        @State private var touching = false

        /// - Parameters:
        ///   - reply: The answer being written, if any.
        ///   - retry: Sends a failed message again.
        ///   - empty: Shown while there are no messages.
        public init(messages: [Message], reply: Reply?, retry: @escaping (Message) -> Void = { _ in },
                    @ViewBuilder empty: () -> Empty) {
            self.messages = messages
            self.reply = reply
            self.retry = retry
            self.empty = empty()
        }

        public var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty && reply == nil {
                        empty.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                        if i == 0 || !Calendar.current.isDate(m.date, inSameDayAs: messages[i - 1].date) {
                            DayStamp(date: m.date)
                        }
                        MessageRow(message: m, retry: retry)
                    }
                    if let reply {
                        ReplyRow(reply: reply)
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
            .onScrollPhaseChange { _, phase in touching = phase == .interacting }
            .onChange(of: reply?.shown) { follow() }
            .onChange(of: reply?.steps) { follow() }
            .onChange(of: reply == nil) { follow() }
            .onChange(of: messages.last?.id) {
                if messages.last?.author == .you {
                    withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
                    atBottom = true
                } else {
                    follow()
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

        /// Keeps the newest text in view, unless you've scrolled away or have a finger on it.
        private func follow() {
            guard atBottom, !touching else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { position.scrollTo(edge: .bottom) }
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

    struct MessageRow: View {
        let message: Message
        let retry: (Message) -> Void

        var body: some View {
            switch message.author {
            case .you:
                VStack(alignment: .trailing, spacing: 6) {
                    Text(message.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.primary.opacity(0.08), in: .rect(cornerRadius: 20))
                        .contextMenu { copy }
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
            case .assistant:
                VStack(alignment: .leading, spacing: 6) {
                    if let label = message.label {
                        Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if !message.steps.isEmpty {
                        FoldedSteps(steps: message.steps, worked: message.worked)
                    }
                    Markdown(message.text)
                        .contextMenu { copy }
                }
            }
        }

        private var copy: some View {
            Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(message.text) }
        }
    }

    /// The answer being written: the steps so far on a line, then the answer as it comes. Once
    /// it's done, its message takes its place with the steps folded away.
    struct ReplyRow: View {
        let reply: Reply

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if !reply.steps.isEmpty {
                    Timeline(steps: reply.steps, live: reply.shown.isEmpty && !reply.ended)
                } else if reply.shown.isEmpty {
                    Working(label: "Thinking")
                }
                if !reply.shown.isEmpty {
                    Markdown(reply.shown, streaming: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reply")
        }
    }

    /// What the assistant is doing, with light running across it.
    public struct Working: View {
        var label: String

        public init(label: String) {
            self.label = label
        }

        public var body: some View {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .overlay {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.clear, .primary.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 60)
                            .offset(x: (phase * 2 - 0.5) * 160 - 30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .mask {
                        Text(label).font(.subheadline.weight(.medium))
                    }
                    .allowsHitTesting(false)
                }
                .contentTransition(.opacity)
                .animation(.smooth, value: label)
                .padding(.vertical, 2)
                .accessibilityLabel(label)
        }
    }
}
