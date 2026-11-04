import SwiftUI

extension Chat {
    /// Markdown as an assistant writes it: paragraphs, headings, lists, quotes, code, tables and
    /// rules, with bold, italics, code and links inside them. The text is split into blocks and each
    /// block is its own view, so while a reply streams only the last block redraws. While
    /// `streaming`, unfinished bold, code and links at the end are closed or held back, so they
    /// never flash as raw symbols.
    public struct Markdown: View {
        var text: String
        var streaming: Bool

        public init(_ text: String, streaming: Bool = false) {
            self.text = text
            self.streaming = streaming
        }

        public var body: some View {
            let blocks = Self.blocks(text)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                    BlockView(block: streaming && i == blocks.count - 1 ? block.healed : block)
                        .equatable()
                }
            }
            // No `.textSelection`: on iOS 27 it takes every tap and hold in the row, so buttons
            // beside the text and the Copy menu never get them.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Blocks

extension Chat.Markdown {
    struct Item: Hashable {
        /// Nesting, from 0.
        var depth: Int
        /// `•`, or the item's number and its `.` or `)`.
        var marker: String
        var text: String
    }

    enum Block: Hashable {
        case paragraph(String)
        case heading(Int, String)
        case list([Item])
        case quote(String)
        /// Its language, and whether the closing fence has arrived.
        case code(String, String, closed: Bool)
        case table([[String]])
        case rule

        /// With an unfinished ending made safe to show: an open `**` or `` ` `` closed, a link
        /// whose address is still coming held back.
        var healed: Block {
            switch self {
            case .paragraph(let t): return .paragraph(Self.heal(t))
            case .heading(let n, let t): return .heading(n, Self.heal(t))
            case .quote(let t): return .quote(Self.heal(t))
            case .list(var items):
                if let last = items.indices.last { items[last].text = Self.heal(items[last].text) }
                return .list(items)
            default: return self
            }
        }

        static func heal(_ text: String) -> String {
            var t = text
            if let open = t.lastIndex(of: "[") {
                let tail = t[open...]
                if !tail.contains("]") || (tail.contains("](") && !tail.contains(")")) { t = String(t[..<open]) }
            }
            // A closer after a space isn't one, so the text being written loses its trailing space.
            var closers = ""
            if t.components(separatedBy: "`").count % 2 == 0 { closers = "`" + closers }
            let inCode = !closers.isEmpty
            if !inCode {
                if t.components(separatedBy: "**").count % 2 == 0 {
                    if t.hasSuffix("**") { t.removeLast(2) } else { closers = "**" + closers }
                }
                if t.replacingOccurrences(of: "**", with: "").count(where: { $0 == "*" }) % 2 == 1 {
                    if t.hasSuffix("*") { t.removeLast() } else { closers = "*" + closers }
                }
            }
            guard !closers.isEmpty else { return t }
            while t.last?.isWhitespace == true { t.removeLast() }
            return t + closers
        }
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var lines = text.components(separatedBy: "\n")[...]
        var paragraph: [String] = []
        func endParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        while let line = lines.popFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                endParagraph()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                var closed = false
                while let next = lines.popFirst() {
                    if next.trimmingCharacters(in: .whitespaces).hasPrefix(fence) { closed = true; break }
                    code.append(next)
                }
                blocks.append(.code(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), code.joined(separator: "\n"), closed: closed))
            } else if trimmed.isEmpty {
                endParagraph()
            } else if let heading = heading(trimmed) {
                endParagraph()
                blocks.append(heading)
            } else if trimmed.count >= 3, Set(trimmed.filter { $0 != " " }).count == 1, "-*_".contains(trimmed.first!) {
                endParagraph()
                blocks.append(.rule)
            } else if trimmed.hasPrefix(">") {
                endParagraph()
                var quote = [String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)]
                while let next = lines.first?.trimmingCharacters(in: .whitespaces), next.hasPrefix(">") {
                    quote.append(String(next.dropFirst()).trimmingCharacters(in: .whitespaces))
                    lines.removeFirst()
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
            } else if trimmed.hasPrefix("|") {
                endParagraph()
                var rows = [line]
                while let next = lines.first, next.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(next)
                    lines.removeFirst()
                }
                blocks.append(.table(rows.compactMap(cells)))
            } else if let first = item(line) {
                endParagraph()
                var items = [first]
                while let next = lines.first {
                    if let item = item(next) {
                        items.append(item)
                    } else if next.hasPrefix("  ") || next.hasPrefix("\t"), !next.trimmingCharacters(in: .whitespaces).isEmpty {
                        // A wrapped line of the item before.
                        items[items.count - 1].text += "\n" + next.trimmingCharacters(in: .whitespaces)
                    } else {
                        break
                    }
                    lines.removeFirst()
                }
                blocks.append(.list(items))
            } else {
                paragraph.append(line)
            }
        }
        endParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(hashes, line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func item(_ line: String) -> Item? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let depth = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        let rest = line.dropFirst(indent.count)
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            return Item(depth: depth, marker: "•", text: String(rest.dropFirst(2)))
        }
        let digits = rest.prefix { $0.isNumber }
        let after = rest.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 3, let dot = after.first, ".)".contains(dot), after.dropFirst().first == " " {
            return Item(depth: depth, marker: "\(digits)\(dot)", text: String(after.dropFirst(2)))
        }
        return nil
    }

    /// A table row's cells; nil for the `|---|:---:|` line under the header.
    private static func cells(_ row: String) -> [String]? {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        let cells = t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } }) { return nil }
        return cells
    }

    /// Bold, italics, code, strikethrough and links. Anything it can't read stays as written.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard var s = try? AttributedString(markdown: text, options: options) else { return AttributedString(text) }
        for run in s.runs where run.inlinePresentationIntent?.contains(.code) == true {
            s[run.range].font = .system(.body, design: .monospaced).weight(.medium)
            s[run.range].backgroundColor = Color.primary.opacity(0.07)
        }
        return s
    }
}

// MARK: Views

extension Chat.Markdown {
    struct BlockView: View, Equatable {
        let block: Block

        var body: some View {
            switch block {
            case .paragraph(let t):
                Text(Chat.Markdown.inline(t))
            case .heading(let level, let t):
                Text(Chat.Markdown.inline(t))
                    .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                    .padding(.top, 4)
            case .list(let items):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.marker)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 14, alignment: .trailing)
                            Text(Chat.Markdown.inline(item.text))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.leading, CGFloat(item.depth) * 18)
                    }
                }
            case .quote(let t):
                Text(Chat.Markdown.inline(t))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.quaternary).frame(width: 3)
                    }
            case .code(let language, let code, _):
                CodeBlock(language: language, code: code)
            case .table(let rows):
                TableBlock(rows: rows)
            case .rule:
                Divider().padding(.vertical, 4)
            }
        }
    }

    struct CodeBlock: View {
        let language: String
        let code: String
        @State private var copied = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(language.isEmpty ? "Code" : language)
                    Spacer()
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        Pasteboard.copy(code)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    }
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
                    .sensoryFeedback(.success, trigger: copied) { _, now in now }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
            }
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 14))
        }
    }

    struct TableBlock: View {
        let rows: [[String]]

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(Chat.Markdown.inline(cell))
                                    .fontWeight(r == 0 ? .semibold : nil)
                                    .fixedSize()
                            }
                        }
                        if r == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                    }
                }
                .font(.subheadline)
                .padding(14)
            }
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 14))
        }
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
