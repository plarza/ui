import SwiftUI

extension Chat {
    /// An assistant's turn, being written or done. While it's written every part shows in order:
    /// thoughts and tools on a line, text as it comes, under a header with how long it's been
    /// working. Once it's done, everything but the answer folds into the header, which opens it
    /// again. The same view shows the turn live and as stored, so finishing moves nothing.
    struct TurnView: View {
        var parts: [Part]
        /// The answer, for a message with no parts.
        var text: String
        var label: String?
        var worked: Duration?
        /// While it's being written: when it started, and whether the stream is still going.
        var live: (started: Date, going: Bool)?

        @State private var open = false

        private var working: Bool { live?.going == true }
        /// The answer: the last text part, once the turn is done.
        private var answer: Int? {
            guard !working else { return nil }
            return parts.lastIndex { $0.kind == .text }
        }
        private var steps: Int { parts.indices.filter { $0 != answer && (parts[$0].kind == .tool || !parts[$0].text.isEmpty) }.count }
        private var shows: Bool { working || open }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if let label {
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                if working || steps > 0 {
                    Header(steps: steps, worked: worked, started: live?.started, working: working, open: $open)
                }
                if parts.isEmpty {
                    if !text.isEmpty { Markdown(text).contextMenu { copy } }
                } else {
                    ForEach(groups, id: \.first) { group in
                        if parts[group.first!].kind == .text {
                            let i = group.first!
                            if i == answer || shows {
                                Markdown(parts[i].text, streaming: working && i == parts.count - 1)
                                    .opacity(i == answer || working ? 1 : 0.7)
                                    .contextMenu { if i == answer { copy } }
                                    .transition(.opacity)
                            }
                        } else if shows {
                            Trace(parts: group.map { parts[$0] }, current: working && group.last == parts.count - 1)
                                .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: shows)
        }

        /// Runs of parts: each text alone, and the thoughts and tools between them together.
        private var groups: [[Int]] {
            var groups: [[Int]] = []
            for (i, part) in parts.enumerated() {
                if part.kind != .text, let last = groups.last?.last, parts[last].kind != .text {
                    groups[groups.count - 1].append(i)
                } else {
                    groups.append([i])
                }
            }
            return groups
        }

        private var copy: some View {
            Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(answer.map { parts[$0].text } ?? text) }
        }
    }

    /// Over a turn: “Working · 12s” while it works, then “Worked for 50s · 9 steps”, which opens and
    /// closes the steps.
    struct Header: View {
        var steps: Int
        var worked: Duration?
        var started: Date?
        var working: Bool
        @Binding var open: Bool

        var body: some View {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 5) {
                    if working, let started {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Working(label: "Working · \(Self.duration(context.date.timeIntervalSince(started)))")
                        }
                    } else {
                        Text(summary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(working)
            .animation(.snappy, value: open)
            .accessibilityValue(working ? "Working" : open ? "Open" : "Closed")
            .accessibilityIdentifier("trace")
        }

        private var summary: String {
            let count = steps == 1 ? "1 step" : "\(steps) steps"
            guard let worked, worked >= .seconds(1) else { return count }
            return "Worked for \(Self.duration(Double(worked.components.seconds))) · \(count)"
        }

        static func duration(_ seconds: Double) -> String {
            Duration.seconds(Int(max(0, seconds))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
        }
    }

    /// Thoughts and tools on a line, top to bottom. The current one, while working, has light running
    /// across it; a thought being written shows its latest lines.
    struct Trace: View {
        var parts: [Part]
        var current: Bool
        @Environment(\.accent) private var accent

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(parts) { part in
                    row(part, now: current && part.id == parts.last?.id)
                }
            }
            .background(alignment: .leading) {
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1.5)
                    .padding(.vertical, 7)
                    .padding(.leading, 2.75)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("steps")
        }

        private func row(_ part: Part, now: Bool) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(now ? AnyShapeStyle(.primary) : AnyShapeStyle(part.kind == .tool ? accent : .secondary.opacity(0.5)))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    switch part.kind {
                    case .thought:
                        Text(part.text.isEmpty ? "Thinking" : part.text)
                            .font(.footnote)
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(now ? 3 : nil)
                            .truncationMode(.head)
                    case .tool, .text:
                        if now {
                            Working(label: part.text)
                        } else {
                            Text(part.text).font(.subheadline.weight(.semibold))
                        }
                        if let detail = part.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                    .mask { Text(label).font(.subheadline.weight(.medium)) }
                    .allowsHitTesting(false)
                }
                .padding(.vertical, 2)
                .accessibilityLabel(label)
        }
    }
}
