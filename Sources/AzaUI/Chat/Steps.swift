import SwiftUI

extension Chat {
    /// One step on the way to an answer: something the assistant thought, or a tool it used.
    public struct Step: Identifiable, Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            case thought, tool
        }

        public var id: Int
        public var kind: Kind
        /// The thought, or what the tool does, like “Looking at COROS”.
        public var text: String
        /// What the tool looked at, like a search or an item's name.
        public var detail: String?

        public init(id: Int, kind: Kind, text: String, detail: String? = nil) {
            self.id = id
            self.kind = kind
            self.text = text
            self.detail = detail
        }
    }

    /// Steps on a line, top to bottom: each thought in italics, each tool with what it looked at.
    /// While `live`, the last one is the step under way.
    struct Timeline: View {
        var steps: [Step]
        var live = false
        @Environment(\.accent) private var accent

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    row(step, current: live && step.id == steps.last?.id)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .background(alignment: .leading) {
                Rectangle()
                    .fill(.primary.opacity(0.14))
                    .frame(width: 1.5)
                    .padding(.vertical, 7)
                    .padding(.leading, 2.75)
            }
            .animation(.smooth, value: steps.count)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("steps")
        }

        private func row(_ step: Step, current: Bool) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(current ? AnyShapeStyle(.primary) : AnyShapeStyle(accent))
                    .frame(width: 7, height: 7)
                    .background { if current { Circle().fill(.primary.opacity(0.18)).padding(-3) } }
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    switch step.kind {
                    case .thought:
                        Text(step.text)
                            .font(.footnote)
                            .italic()
                            .foregroundStyle(.secondary)
                            // A thought being written shows its latest lines.
                            .lineLimit(current ? 4 : nil)
                            .truncationMode(current ? .head : .tail)
                    case .tool:
                        if current {
                            Working(label: step.text)
                        } else {
                            Text(step.text).font(.subheadline.weight(.semibold))
                        }
                        if let detail = step.detail {
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

    /// A finished answer's steps, folded into one line above it, like “Worked for 14s · 5 steps”.
    /// Tap it to see them again.
    struct FoldedSteps: View {
        var steps: [Step]
        var worked: Duration?
        @State private var open = false

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { open.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(summary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "Open" : "Closed")
                .accessibilityIdentifier("foldedSteps")
                if open {
                    Timeline(steps: steps)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
        }

        private var summary: String {
            let count = steps.count == 1 ? "1 step" : "\(steps.count) steps"
            guard let worked, worked >= .seconds(1) else { return count }
            let time = worked.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
            return "Worked for \(time) · \(count)"
        }
    }
}
