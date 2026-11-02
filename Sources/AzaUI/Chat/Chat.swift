import Foundation

/// A chat with an AI: `Chat.Transcript` shows the messages and the reply being written,
/// `Chat.Composer` writes the next message, `Chat.Reply` paces a streamed answer and
/// `Chat.Markdown` renders it. `ServerSentEvents.follow` reads the stream and picks it back up
/// after a dropped connection. Where messages are stored and how they're sent is the app's.
public enum Chat {}

extension Chat {
    public struct Message: Identifiable, Hashable, Sendable {
        public enum Author: Hashable, Sendable {
            case you, assistant
        }

        public enum State: Hashable, Sendable {
            case sent
            /// Shown at once, before the server has it.
            case sending
            /// Didn't reach the server: the reason, and a retry.
            case failed(String)
        }

        public var id: String
        public var author: Author
        public var text: String
        public var date: Date
        /// A line above an assistant message saying why it came, like “After your run”.
        public var label: String?
        public var state: State
        /// How the assistant got to its answer, folded into one line above it.
        public var steps: [Step]
        /// How long the assistant worked on its answer.
        public var worked: Duration?

        public init(id: String, author: Author, text: String, date: Date, label: String? = nil, state: State = .sent,
                    steps: [Step] = [], worked: Duration? = nil) {
            self.id = id
            self.author = author
            self.text = text
            self.date = date
            self.label = label
            self.state = state
            self.steps = steps
            self.worked = worked
        }
    }
}
