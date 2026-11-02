import Foundation

/// One server-sent event.
nonisolated public struct ServerSentEvent: Sendable, Equatable {
    public var id: String?
    public var event: String
    public var data: String

    public init(id: String? = nil, event: String = "message", data: String) {
        self.id = id
        self.event = event
        self.data = data
    }
}

/// Server-sent events (the WHATWG `text/event-stream` format) over URLSession.
nonisolated public enum ServerSentEvents {
    public struct HTTPError: LocalizedError, Sendable {
        public var status: Int
        public var body: Data
        public var errorDescription: String? {
            struct E: Decodable { var error: String }
            return (try? JSONDecoder().decode(E.self, from: body).error) ?? "The server answered \(status)"
        }
    }

    /// Follows a stream across dropped connections. Each attempt builds its request from the last
    /// event ID seen (send it as `Last-Event-ID`), so the server can carry on from there. Ends at
    /// the event `isLast` picks, or when the server answers 204 (nothing to follow). Gives up after
    /// `attempts` tries in a row that brought nothing new, or at once on an HTTP error.
    public static func follow(
        session: URLSession = .shared,
        attempts: Int = 6,
        isLast: @escaping @Sendable (ServerSentEvent) -> Bool,
        request: @escaping @Sendable (_ lastEventID: String?) async throws -> URLRequest
    ) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @concurrent in
                var last: String?
                var failures = 0
                while !Task.isCancelled {
                    do {
                        let (bytes, response) = try await session.bytes(for: try await request(last))
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if status == 204 { break }
                        guard status == 200 else {
                            var body = Data()
                            for try await b in bytes { body.append(b) }
                            throw HTTPError(status: status, body: body)
                        }
                        for try await event in events(bytes) {
                            failures = 0
                            if let id = event.id { last = id }
                            continuation.yield(event)
                            if isLast(event) {
                                continuation.finish()
                                return
                            }
                        }
                        // The server closed the stream early: go round again.
                    } catch let error as HTTPError {
                        continuation.finish(throwing: error)
                        return
                    } catch {
                        if Task.isCancelled { break }
                        failures += 1
                        if failures >= attempts {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    // 0.25 s, 0.5, 1, 2, 4, capped at 8.
                    try? await Task.sleep(for: .milliseconds(min(8000, 250 << max(0, failures - 1))))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The events in a byte stream.
    public static func events<Bytes: AsyncSequence & Sendable>(_ bytes: Bytes) -> AsyncThrowingStream<ServerSentEvent, Error> where Bytes.Element == UInt8 {
        AsyncThrowingStream { continuation in
            let task = Task { @concurrent in
                var parser = Parser()
                do {
                    for try await byte in bytes {
                        if let event = parser.take(byte) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Lines in, events out. Lines end in LF, CR LF or CR; a blank line ends an event.
    public struct Parser: Sendable {
        private var line: [UInt8] = []
        private var afterCR = false
        private var id: String?
        private var event: String?
        private var data: [String] = []
        private var hasData = false

        public init() {}

        public mutating func take(_ byte: UInt8) -> ServerSentEvent? {
            if afterCR {
                afterCR = false
                if byte == 0x0A { return nil }
            }
            switch byte {
            case 0x0D:
                afterCR = true
                return endLine()
            case 0x0A:
                return endLine()
            default:
                line.append(byte)
                return nil
            }
        }

        private mutating func endLine() -> ServerSentEvent? {
            defer { line.removeAll(keepingCapacity: true) }
            if line.isEmpty {
                defer { event = nil; data = []; hasData = false }
                guard hasData else { return nil }
                return ServerSentEvent(id: id, event: event ?? "message", data: data.joined(separator: "\n"))
            }
            let text = String(decoding: line, as: UTF8.self)
            if text.hasPrefix(":") { return nil }
            var field = text[...]
            var value: Substring = ""
            if let colon = text.firstIndex(of: ":") {
                field = text[..<colon]
                value = text[text.index(after: colon)...]
                // One space after the colon is the format's; any more are the data's, like the
                // space before a streamed word.
                if value.first == " " { value = value.dropFirst() }
            }
            switch field {
            case "event": event = String(value)
            case "data": data.append(String(value)); hasData = true
            case "id" where !value.contains("\0"): id = String(value)
            default: break
            }
            return nil
        }
    }
}
