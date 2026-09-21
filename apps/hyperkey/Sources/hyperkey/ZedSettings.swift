import Foundation

/// Zed's theme, set in Zed's own ~/.config/zed/settings.json.
///
/// This is the Swift half of scripts/lib/zed-settings.sh — the third rewrite
/// that exists twice, for the same reason as the other two: the launcher ships
/// as a signed bundle and cannot reach the checkout those scripts live in.
/// Neither half is trusted alone; ZedSettingsParityTests runs both over the
/// same fixtures and insists their output matches byte for byte.
///
/// Zed differs from VS Code in the two ways that shape everything here.
///
/// First, `theme` takes either a name or an object — {"mode": "system",
/// "light": …, "dark": …} — which is Zed's equivalent of VS Code's
/// window.autoDetectColorScheme. Omaccy drives the theme once its editor
/// switch is on, so the object is replaced outright by the plain name. That
/// means the value being rewritten can span several lines, which the
/// single-line rewrite in OmaccyAppearance.settings has no way to do, and why
/// this walks the file character by character instead of line by line.
///
/// Second, Zed has no `--install-extension` CLI. Its documented route is
/// `auto_install_extensions`, an object of extension ids Zed installs at its
/// next launch, so following a theme means merging one key into an object
/// rather than running a command.
enum OmaccyZedSettings {
    /// Where a top-level key's value starts and ends: its first and last
    /// non-whitespace characters outside comments. Ending at the value rather
    /// than at the comma that follows keeps a trailing comment on the same
    /// line out of the span. Lines and columns are 1-based, the way the awk
    /// half indexes them.
    private struct Span {
        let key: String
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int
    }

    /// The settings file with `theme` set to `theme` and `extensionID` merged
    /// into `auto_install_extensions`. Nil when the file's shape leaves
    /// nowhere safe to put the theme, which is left alone rather than guessed
    /// at. A nil or empty `extensionID` is a palette Zed has built in, which
    /// needs no install.
    static func settings(_ contents: String, theme: String, extensionID: String?) -> String? {
        // A quote or backslash could only come from a misread theme file and
        // would write broken JSON; an extension id is a registry slug or
        // nothing.
        guard !theme.isEmpty, !theme.contains("\""), !theme.contains("\\") else { return nil }
        var identifier = extensionID ?? ""
        if identifier.contains(where: { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }) {
            identifier = ""
        }

        var lines = contents.components(separatedBy: "\n")
        // awk's RS does not make a record out of the empty string after a
        // final newline, so neither does this.
        if lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        var characters = lines.map(Array.init)

        let scan = Scanner(lines: characters)
        guard let topLine = scan.topLine else { return nil }
        let spans = scan.spans

        let unit = indentUnit(characters)
        var dropped = Set<Int>()
        var after: [Int: String] = [:]
        var pendingTop: [String] = []

        if let span = spans.first(where: { $0.key == "theme" }) {
            // The value may run over several lines — an object always does —
            // so the span collapses onto the line it started on, and the lines
            // it covered below that one go away.
            let last = characters[span.endLine - 1]
            let terminator = carriageReturn(last)
            let head = prefix(characters[span.startLine - 1], span.startColumn - 1)
            let tail = suffix(body(last), from: span.endColumn + 1)
            characters[span.startLine - 1] = Array("\(head)\"\(theme)\"\(tail)\(terminator)")
            if span.endLine > span.startLine {
                for index in (span.startLine + 1)...span.endLine { dropped.insert(index) }
            }
        } else {
            // No entry yet, so it goes in right below the opening brace. Only
            // a brace that ends its line is handled; a hand-packed object is
            // left alone rather than guessed at.
            guard endsWithOpenBrace(characters[topLine - 1]) else { return nil }
            pendingTop.append("\"theme\": \"\(theme)\"")
        }

        if !identifier.isEmpty {
            mergeExtension(identifier, into: &characters, spans: spans, topLine: topLine,
                           unit: unit, after: &after, pendingTop: &pendingTop)
        }

        // Entries bound for the top-level object are held back rather than
        // written as they are decided, because the comma each one needs
        // depends on how many follow it — and into an object that started out
        // empty, the first of two inserts needs one where the last does not.
        if !pendingTop.isEmpty {
            let terminator = carriageReturn(characters[topLine - 1])
            var block = after[topLine] ?? ""
            for (offset, entry) in pendingTop.enumerated() {
                let comma = (offset < pendingTop.count - 1 || !spans.isEmpty) ? "," : ""
                block += "\(unit)\(entry)\(comma)\(terminator)\n"
            }
            after[topLine] = block
        }

        var output = ""
        for index in 1...characters.count {
            if !dropped.contains(index) { output += String(characters[index - 1]) + "\n" }
            if let block = after[index] { output += block }
        }
        // The shell half writes through awk, which terminates every record,
        // and then takes that byte back off a file that never ended in one.
        // Both tests are on the last *byte*, not the last Character: Swift
        // reads "\r\n" as a single grapheme cluster, so `hasSuffix("\n")` is
        // false for every CRLF file and `removeLast()` would take the
        // carriage return with it — which is exactly how this first disagreed
        // with the awk half.
        if contents.utf8.last != 0x0A {
            output = String(decoding: output.utf8.dropLast(), as: UTF8.self)
        }
        return output
    }

    private static func mergeExtension(_ identifier: String, into characters: inout [[Character]],
                                       spans: [Span], topLine: Int, unit: String,
                                       after: inout [Int: String], pendingTop: inout [String]) {
        guard let span = spans.first(where: { $0.key == "auto_install_extensions" }) else {
            guard endsWithOpenBrace(characters[topLine - 1]) else { return }
            pendingTop.append("\"auto_install_extensions\": { \"\(identifier)\": true }")
            return
        }
        let text = valueText(characters, span)
        // Anything but an object is someone else's shape, and merging into it
        // would be a guess.
        guard text.first == "{" else { return }
        // Already listed — as true, or as false by someone who does not want
        // it — so it stays exactly as it is.
        if containsKey(identifier, in: text) { return }
        // An object with no entries of its own takes no separating comma.
        let inner = text.dropFirst().dropLast()
        let empty = !inner.contains { !$0.isWhitespace }
        let separator = empty ? "" : ", "

        let line = characters[span.startLine - 1]
        let terminator = carriageReturn(line)
        let stripped = body(line)
        let head = prefix(stripped, span.startColumn)
        var tail = suffix(stripped, from: span.startColumn + 1)
        if tail.contains(where: { $0 != " " && $0 != "\t" }) || span.startLine == span.endLine {
            // Something follows the brace on its line, so the entry goes
            // inline and the file keeps every line break it had. The spacing
            // the brace already had is reused, so `{ "html": true }` does not
            // come back as `{"tokyo-night": true,  "html": true }`.
            let gap = String(tail.prefix { $0 == " " || $0 == "\t" })
            tail = String(tail.dropFirst(gap.count))
            characters[span.startLine - 1] =
                Array("\(head)\(gap)\"\(identifier)\": true\(separator)\(tail)\(terminator)")
        } else {
            // The brace ends its line, so the entry gets a line of its own,
            // one level in from the line the object opened on.
            characters[span.startLine - 1] = Array("\(head)\(tail)\(terminator)")
            let indent = String(stripped.prefix { $0 == " " || $0 == "\t" })
            let comma = empty ? "" : ","
            after[span.startLine] =
                "\(indent)\(unit)\"\(identifier)\": true\(comma)\(terminator)\n" + (after[span.startLine] ?? "")
        }
    }

    // MARK: - Walking the file

    /// One pass over the file, tracking strings, both comment forms, and brace
    /// depth, so that only the top-level object's keys are recorded. A nested
    /// `"theme"` — Zed has one under `terminal` — belongs to its own object
    /// and is none of Omaccy's business.
    private struct Scanner {
        private(set) var spans: [Span] = []
        private(set) var topLine: Int?

        init(lines: [[Character]]) {
            var depth = 0
            var inString = false
            var escaped = false
            var inBlock = false
            var awaiting = ""
            var pending = ""
            var current = ""
            var name = ""
            var firstLine = 0, firstColumn = 0, lastLine = 0, lastColumn = 0

            func closeValue() {
                awaiting = "key"
                guard firstLine != 0 else { return }
                spans.append(Span(key: name, startLine: firstLine, startColumn: firstColumn,
                                  endLine: lastLine, endColumn: lastColumn))
            }

            for (lineOffset, line) in lines.enumerated() {
                let i = lineOffset + 1
                var j = 1
                while j <= line.count {
                    let c = line[j - 1]
                    let ahead: Character? = j < line.count ? line[j] : nil
                    if inBlock {
                        if c == "*" && ahead == "/" { inBlock = false; j += 1 }
                        j += 1
                        continue
                    }
                    if !inString && c == "/" {
                        if ahead == "/" { break }
                        if ahead == "*" { inBlock = true; j += 2; continue }
                    }
                    let terminates = !inString && depth == 1 && awaiting == "value"
                        && (c == "," || c == "}" || c == "]")
                    if awaiting == "value" && !terminates && c != " " && c != "\t" && c != "\r" {
                        if firstLine == 0 { firstLine = i; firstColumn = j }
                        lastLine = i; lastColumn = j
                    }
                    if inString {
                        if escaped { escaped = false }
                        else if c == "\\" { escaped = true }
                        else if c == "\"" {
                            inString = false
                            if depth == 1 && awaiting == "key" { pending = current }
                        } else { current.append(c) }
                        j += 1
                        continue
                    }
                    if c == "\"" { inString = true; current = ""; j += 1; continue }
                    if c == "{" || c == "[" {
                        depth += 1
                        if depth == 1 && c == "{" && topLine == nil {
                            topLine = i
                            awaiting = "key"
                        }
                        j += 1
                        continue
                    }
                    if c == "}" || c == "]" {
                        if terminates { closeValue() }
                        depth -= 1
                        j += 1
                        continue
                    }
                    if depth == 1 && c == ":" && awaiting == "key" {
                        awaiting = "value"
                        name = pending
                        firstLine = 0; lastLine = 0
                        j += 1
                        continue
                    }
                    if terminates && c == "," { closeValue() }
                    j += 1
                }
            }
        }
    }

    // MARK: - Line helpers

    /// A value's own text, newlines and all, for looking inside an object
    /// without a second parser.
    private static func valueText(_ lines: [[Character]], _ span: Span) -> String {
        var text = ""
        for index in span.startLine...span.endLine {
            let line = lines[index - 1]
            let from = index == span.startLine ? span.startColumn : 1
            let to = index == span.endLine ? span.endColumn : line.count
            if from <= to { text += String(line[(from - 1)..<to]) }
            if index < span.endLine { text += "\n" }
        }
        return text
    }

    /// Whether the object already names this extension, as a key rather than
    /// somewhere inside a value.
    private static func containsKey(_ identifier: String, in text: String) -> Bool {
        let quoted = Array("\"\(identifier)\"")
        let characters = Array(text)
        var index = 0
        while index + quoted.count <= characters.count {
            if Array(characters[index..<(index + quoted.count)]) == quoted {
                var after = index + quoted.count
                while after < characters.count,
                      characters[after] == " " || characters[after] == "\t"
                        || characters[after] == "\r" || characters[after] == "\n" {
                    after += 1
                }
                if after < characters.count && characters[after] == ":" { return true }
            }
            index += 1
        }
        return false
    }

    /// The file's own indent unit, read off its first indented line, so an
    /// inserted line sits the way the rest of the file does.
    private static func indentUnit(_ lines: [[Character]]) -> String {
        for line in lines {
            guard line.contains(where: { $0 != " " && $0 != "\t" && $0 != "\r" }) else { continue }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            if !indent.isEmpty { return String(indent) }
        }
        return "  "
    }

    /// Whether a brace ends this line, which is the only shape an inserted
    /// top-level entry is placed under.
    private static func endsWithOpenBrace(_ line: [Character]) -> Bool {
        var rest = ArraySlice(body(line))
        while let last = rest.last, last == " " || last == "\t" { rest = rest.dropLast() }
        return rest.last == "{"
    }

    private static func carriageReturn(_ line: [Character]) -> String {
        line.last == "\r" ? "\r" : ""
    }

    private static func body(_ line: [Character]) -> [Character] {
        line.last == "\r" ? Array(line.dropLast()) : line
    }

    private static func prefix(_ line: [Character], _ count: Int) -> String {
        count <= 0 ? "" : String(line.prefix(count))
    }

    private static func suffix(_ line: [Character], from column: Int) -> String {
        column > line.count ? "" : String(line[(column - 1)...])
    }
}
