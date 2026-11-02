import Foundation

/// A chat with an AI. `Chat.Transcript` shows the messages and the turn being written,
/// `Chat.Composer` writes the next message, `Chat.Turn` takes a streamed turn as it comes and
/// `Chat.Markdown` renders text. `ServerSentEvents.follow` reads the stream and picks it back up
/// after a dropped connection. Where messages are stored and how they're sent is the app's.
///
/// An assistant's turn is its parts in order: what it thought, the tools it used and what it wrote.
/// While it works the parts show as they come, and nothing on screen is ever taken back: text only
/// grows. Once it's done, everything but its answer folds into one line, like “Worked for 14s ·
/// 5 steps”, that opens to show it all again. A turn being written and the message it's stored as
/// share an ID and a view, so the one becomes the other without anything moving.
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
        /// The message, or the assistant's answer: what Copy copies.
        public var text: String
        public var date: Date
        /// A line above an assistant message saying why it came, like “After your run”.
        public var label: String?
        public var state: State
        /// The assistant's turn in order. Empty for a message that's only its `text`.
        public var parts: [Part]
        /// How long the assistant worked on it.
        public var worked: Duration?

        public init(id: String, author: Author, text: String, date: Date, label: String? = nil, state: State = .sent,
                    parts: [Part] = [], worked: Duration? = nil) {
            self.id = id
            self.author = author
            self.text = text
            self.date = date
            self.label = label
            self.state = state
            self.parts = parts
            self.worked = worked
        }
    }

    /// One part of an assistant's turn.
    public struct Part: Identifiable, Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            /// Something it thought.
            case thought
            /// A tool it used: `text` is what the tool does, like “Looking at COROS”.
            case tool
            /// Something it wrote. The last is the answer.
            case text
        }

        /// Its place in the turn, from 0.
        public var id: Int
        public var kind: Kind
        public var text: String
        /// What the tool looked at, like a search or a file.
        public var detail: String?

        public init(id: Int, kind: Kind, text: String, detail: String? = nil) {
            self.id = id
            self.kind = kind
            self.text = text
            self.detail = detail
        }
    }
}
