import Foundation
import Observation

extension Chat {
    /// An assistant's turn as it streams in. Each event adds to the last part or starts a new one,
    /// so what's on screen only ever grows. Text arrives in bursts; `parts` lets the text being
    /// written out at an even pace, a little behind, so it reads as written rather than jumping a
    /// line at a time. The further behind it is, the faster it catches up.
    @MainActor @Observable
    public final class Turn {
        /// The ID the finished turn is stored under.
        public let id: String
        /// When the assistant started.
        public let started: Date
        /// The parts so far, as shown.
        public private(set) var parts: [Part] = []
        /// The stream has ended; the text may still be catching up.
        public private(set) var ended = false

        /// The text part being written, in full; `parts` has as much of it as is shown.
        private var writing = ""
        private var shown = 0
        private var pacing: Task<Void, Never>?

        public init(id: String, started: Date = .now) {
            self.id = id
            self.started = started
        }

        /// A new thought.
        public func think() { add(.thought) }

        /// More of the thought under way.
        public func thinking(_ more: String) {
            if parts.last?.kind != .thought { add(.thought) }
            parts[parts.count - 1].text += more
        }

        /// A tool, by what it does, like “Looking at COROS”.
        public func use(_ tool: String) { add(.tool, tool) }

        /// What the last tool looked at, once it's known.
        public func detail(_ detail: String) {
            guard let i = parts.lastIndex(where: { $0.kind == .tool }) else { return }
            parts[i].detail = detail
        }

        /// A new block of text.
        public func say() { add(.text) }

        /// More of the text being written.
        public func write(_ more: String) {
            if parts.last?.kind != .text { add(.text) }
            writing += more
            pace()
        }

        /// The stream has ended.
        public func end() { ended = true }

        /// Whether anything is still to come or still to show.
        public var isActive: Bool { !ended || shown < writing.count }

        /// Returns once all the text is shown, so the stored message can take the turn's place.
        public func settle() async {
            while shown < writing.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
            }
        }

        private func add(_ kind: Part.Kind, _ text: String = "") {
            flush()
            // A part that never got anything gives way to what comes next.
            if let last = parts.last, last.kind != .tool, last.text.isEmpty { parts.removeLast() }
            parts.append(Part(id: parts.count, kind: kind, text: text))
        }

        /// Shows all of the text being written before another part starts.
        private func flush() {
            guard shown < writing.count, let i = parts.lastIndex(where: { $0.kind == .text }) else {
                writing = ""
                shown = 0
                return
            }
            parts[i].text = writing
            writing = ""
            shown = 0
        }

        private func pace() {
            guard pacing == nil else { return }
            pacing = Task { [weak self] in
                while let self, !Task.isCancelled {
                    let total = self.writing.count
                    guard self.shown < total, let i = self.parts.indices.last, self.parts[i].kind == .text else { break }
                    // A tenth of what's waiting each frame, at least one character.
                    self.shown = min(total, self.shown + max(1, (total - self.shown + 9) / 10))
                    self.parts[i].text = String(self.writing.prefix(self.shown))
                    try? await Task.sleep(for: .milliseconds(16))
                }
                self?.pacing = nil
            }
        }
    }
}
