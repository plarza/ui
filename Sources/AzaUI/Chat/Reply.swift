import Foundation
import Observation

extension Chat {
    /// An answer as it streams in, and the steps on the way to it. Text arrives in bursts; `shown`
    /// lets it out at an even pace, a little behind, so the reply reads as if written rather than
    /// jumping a line at a time. The further behind it is, the faster it catches up, so it's never
    /// more than a fraction of a second behind.
    @MainActor @Observable
    public final class Reply {
        /// Everything received.
        public private(set) var text = ""
        /// What's on screen so far.
        public private(set) var shown = ""
        /// What the assistant thought and the tools it used, in order. The last is the step under
        /// way until the answer starts.
        public private(set) var steps: [Step] = []
        /// The stream has ended; `shown` may still be catching up.
        public private(set) var ended = false

        private var count = 0
        private var pacing: Task<Void, Never>?

        public init() {}

        /// Picks up a reply partway through, as it was before the app closed: shown at once.
        public init(text: String) {
            self.text = text
            shown = text
            count = text.count
        }

        /// More of the answer.
        public func append(_ more: String) {
            text += more
            pace()
        }

        /// Starts the answer again: what came before was the assistant thinking aloud, and becomes
        /// a thought.
        public func restart() {
            let aloud = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !aloud.isEmpty { add(.thought, aloud) }
            text = ""
            shown = ""
            count = 0
        }

        /// A new thought starts.
        public func think() {
            add(.thought, "")
        }

        /// More of the thought under way.
        public func thinking(_ more: String) {
            if steps.last?.kind != .thought { think() }
            steps[steps.count - 1].text += more
        }

        /// The assistant uses a tool: what it does, like “Looking at COROS”.
        public func use(_ tool: String, detail: String? = nil) {
            add(.tool, tool, detail: detail)
        }

        /// What the tool under way looked at, once it's known.
        public func detail(_ detail: String) {
            guard let i = steps.lastIndex(where: { $0.kind == .tool }) else { return }
            steps[i].detail = detail
        }

        /// The stream has ended.
        public func end() {
            ended = true
        }

        private func add(_ kind: Step.Kind, _ text: String, detail: String? = nil) {
            // An empty thought that never got any text gives way to what comes next.
            if let last = steps.last, last.kind == .thought, last.text.isEmpty { steps.removeLast() }
            steps.append(Step(id: steps.count, kind: kind, text: text, detail: detail))
        }

        /// Whether anything is still to come or still to show.
        public var isActive: Bool { !ended || count < text.count }

        /// Returns once everything received is on screen, so the finished message can take the
        /// reply's place without a jump.
        public func settle() async {
            while count < text.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
            }
        }

        private func pace() {
            guard pacing == nil else { return }
            pacing = Task { [weak self] in
                while let self, !Task.isCancelled {
                    let total = self.text.count
                    guard self.count < total else { break }
                    // A tenth of what's waiting each frame, at least one character.
                    self.count = min(total, self.count + max(1, (total - self.count + 9) / 10))
                    self.shown = String(self.text.prefix(self.count))
                    try? await Task.sleep(for: .milliseconds(16))
                }
                self?.pacing = nil
            }
        }
    }
}
