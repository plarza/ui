import Foundation
import Observation

extension Chat {
    /// An answer as it streams in. Text arrives in bursts; `shown` lets it out at an even pace, a
    /// little behind, so the reply reads as if written rather than jumping a line at a time. The
    /// further behind it is, the faster it catches up, so it's never more than a fraction of a
    /// second behind.
    @MainActor @Observable
    public final class Reply {
        /// Everything received.
        public private(set) var text = ""
        /// What's on screen so far.
        public private(set) var shown = ""
        /// What the assistant is doing instead of writing, like “Reading your runs”.
        public private(set) var activity: String?
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
            activity = nil
            pace()
        }

        /// Starts the answer again: what came before was the assistant thinking aloud.
        public func restart() {
            text = ""
            shown = ""
            count = 0
        }

        /// The assistant is doing something, like using a tool.
        public func doing(_ activity: String) {
            self.activity = activity
        }

        /// The stream has ended.
        public func end() {
            ended = true
            activity = nil
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
