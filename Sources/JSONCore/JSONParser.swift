import Foundation

public struct JSONParseError: Error {
    public let message: String
    public let suggestion: String?
    public let line: Int
    public let column: Int
}

public struct AutoFixNote {
    public let message: String
    public let line: Int
    public let column: Int
}

/// A single hand-written JSON parser used in two modes:
/// - strict: rejects anything that isn't valid JSON, with a precise
///   line/column and a human suggestion for what to change.
/// - lenient: tolerates common mistakes (trailing commas, single quotes,
///   unquoted keys, comments, Python literals, ...), logging each as a
///   fix. Serializing the result is the "corrected" JSON.
public final class JSONParser {
    private let chars: [Character]
    private var pos: Int = 0
    private var line: Int = 1
    private var col: Int = 1
    private let lenient: Bool
    public private(set) var fixes: [AutoFixNote] = []
    private var depth = 0
    /// Recursion-depth ceiling. Each `{` or `[` costs a few stack frames;
    /// without a limit, pathologically deep input (or a tiny stack on a
    /// background thread) can overflow the call stack and crash instead of
    /// producing a normal parse error.
    private let maxDepth = 500

    public init(_ text: String, lenient: Bool) {
        self.chars = Array(text)
        self.lenient = lenient
    }

    public func parse() throws -> JSONNode {
        try skipWhitespaceAndComments()
        let value = try parseValue()
        try skipWhitespaceAndComments()
        if pos < chars.count {
            throw error(
                "Unexpected extra content after the JSON value",
                suggestion: "Remove everything after the final closing '}' or ']'."
            )
        }
        return value
    }

    // MARK: - Low-level cursor helpers

    private func current() -> Character? {
        pos < chars.count ? chars[pos] : nil
    }

    private func peek(_ offset: Int) -> Character? {
        let i = pos + offset
        return i < chars.count ? chars[i] : nil
    }

    @discardableResult
    private func advance() -> Character? {
        guard pos < chars.count else { return nil }
        let c = chars[pos]
        pos += 1
        if c == "\n" {
            line += 1
            col = 1
        } else {
            col += 1
        }
        return c
    }

    private func error(_ message: String, suggestion: String? = nil) -> JSONParseError {
        JSONParseError(message: message, suggestion: suggestion, line: line, column: col)
    }

    private func recordFix(_ message: String) {
        fixes.append(AutoFixNote(message: message, line: line, column: col))
    }

    // MARK: - Whitespace & comments

    /// Unicode "space" and zero-width/format characters that aren't valid
    /// JSON whitespace but routinely sneak in from copy-pasting (from
    /// rich text, web pages, chat apps, PDFs, a BOM at the start of a
    /// file, ...). A pasted document otherwise identical to valid JSON
    /// fails with a confusing "expected key/value" error at the exact
    /// point one of these sits, because it isn't recognized as either
    /// whitespace or a token start.
    private static let invisibleWhitespaceScalars: Set<UInt32> = [
        0x00A0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x200B, 0x200C, 0x200D,
        0x2028, 0x2029,
        0x202F, 0x205F,
        0x2060,
        0x3000,
        0xFEFF
    ]

    private func invisibleWhitespaceScalar(at c: Character) -> Unicode.Scalar? {
        guard c.unicodeScalars.count == 1, let scalar = c.unicodeScalars.first,
              JSONParser.invisibleWhitespaceScalars.contains(scalar.value) else { return nil }
        return scalar
    }

    private func skipWhitespaceAndComments() throws {
        while let c = current() {
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                advance()
                continue
            }
            if let scalar = invisibleWhitespaceScalar(at: c) {
                let hex = String(format: "U+%04X", scalar.value)
                if lenient {
                    recordFix("Removed an invisible/non-standard space character (\(hex)), likely left over from copy-pasting")
                    advance()
                    continue
                } else {
                    throw error(
                        "Found an invisible character (\(hex)) here, which isn't valid JSON whitespace",
                        suggestion: "This is usually left over from copy-pasting from a web page, chat app, or rich text. Delete it, or use Auto-Fix to remove it automatically."
                    )
                }
            }
            if c == "/" && peek(1) == "/" {
                if !lenient {
                    // Leave it; caller context will produce a clear error.
                    return
                }
                recordFix("Removed '//' comment")
                while let c2 = current(), c2 != "\n" { advance() }
                continue
            }
            if c == "/" && peek(1) == "*" {
                if !lenient { return }
                recordFix("Removed '/* ... */' comment")
                advance(); advance()
                while current() != nil && !(current() == "*" && peek(1) == "/") { advance() }
                advance(); advance()
                continue
            }
            break
        }
    }

    // MARK: - Values

    private func matchKeyword(_ keyword: String) -> Bool {
        let kw = Array(keyword)
        guard pos + kw.count <= chars.count else { return false }
        for i in 0..<kw.count where chars[pos + i] != kw[i] { return false }
        // Don't match a prefix of a longer identifier (e.g. "trueFoo").
        if let after = peek(kw.count), after.isLetter || after.isNumber || after == "_" || after == "$" {
            return false
        }
        for _ in 0..<kw.count { advance() }
        return true
    }

    private func parseValue() throws -> JSONNode {
        try skipWhitespaceAndComments()
        guard let c = current() else {
            throw error(
                "Unexpected end of input — expected a value",
                suggestion: "Add a value: a string, number, object, array, true, false, or null."
            )
        }

        switch c {
        case "{":
            return try parseObject()
        case "[":
            return try parseArray()
        case "\"":
            return .string(try parseQuotedString(delimiter: "\""))
        case "'":
            if lenient {
                let s = try parseQuotedString(delimiter: "'")
                recordFix("Converted single-quoted string to double quotes")
                return .string(s)
            } else {
                throw error(
                    "Strings must use double quotes, not single quotes",
                    suggestion: "Replace ' with \"."
                )
            }
        case "/" where lenient && peek(1) == "/":
            try skipWhitespaceAndComments()
            return try parseValue()
        case "/" where lenient && peek(1) == "*":
            try skipWhitespaceAndComments()
            return try parseValue()
        default:
            if c.isNumber || c == "-" {
                return try parseNumber()
            }
            if c == "." && lenient {
                return try parseNumber()
            }
            if matchKeyword("true") { return .bool(true) }
            if matchKeyword("false") { return .bool(false) }
            if matchKeyword("null") { return .null }
            if lenient {
                if matchKeyword("True") { recordFix("Converted Python 'True' to 'true'"); return .bool(true) }
                if matchKeyword("False") { recordFix("Converted Python 'False' to 'false'"); return .bool(false) }
                if matchKeyword("None") { recordFix("Converted Python 'None' to 'null'"); return .null }
                if matchKeyword("NaN") { recordFix("Converted 'NaN' to 'null' (JSON has no NaN)"); return .null }
                if matchKeyword("Infinity") { recordFix("Converted 'Infinity' to 'null' (JSON has no Infinity)"); return .null }
                if matchKeyword("-Infinity") { recordFix("Converted '-Infinity' to 'null' (JSON has no Infinity)"); return .null }
                if matchKeyword("undefined") { recordFix("Converted 'undefined' to 'null'"); return .null }
            } else {
                // Give a specific hint for the common non-JSON literals.
                if matchesWord("True") || matchesWord("False") || matchesWord("None") {
                    throw error(
                        "JSON is case-sensitive — use lowercase true/false/null",
                        suggestion: "Change this to 'true', 'false', or 'null'."
                    )
                }
            }
            throw error(
                "Unexpected character '\(c)' — expected a value",
                suggestion: "Expected a string, number, object '{', array '[', true, false, or null."
            )
        }
    }

    private func matchesWord(_ word: String) -> Bool {
        let kw = Array(word)
        guard pos + kw.count <= chars.count else { return false }
        for i in 0..<kw.count where chars[pos + i] != kw[i] { return false }
        return true
    }

    // MARK: - Object / Array

    private func parseObject() throws -> JSONNode {
        depth += 1
        defer { depth -= 1 }
        if depth > maxDepth {
            throw error("JSON is nested too deeply (over \(maxDepth) levels)", suggestion: "This is likely malformed or an extreme edge case rather than real data.")
        }
        advance() // consume '{'
        try skipWhitespaceAndComments()
        var pairs: [(String, JSONNode)] = []

        if current() == "}" { advance(); return .object(pairs) }

        while true {
            try skipWhitespaceAndComments()
            let key = try parseKey()
            try skipWhitespaceAndComments()
            guard current() == ":" else {
                throw error(
                    "Expected ':' after key \"\(key)\"",
                    suggestion: "Add a colon between the key and its value."
                )
            }
            advance()
            try skipWhitespaceAndComments()
            let value = try parseValue()
            pairs.append((key, value))
            try skipWhitespaceAndComments()

            if current() == "," {
                advance()
                try skipWhitespaceAndComments()
                if current() == "}" {
                    if lenient {
                        advance()
                        recordFix("Removed trailing comma before '}'")
                        return .object(pairs)
                    } else {
                        throw error(
                            "Trailing comma is not allowed before '}'",
                            suggestion: "Remove the comma after the last property."
                        )
                    }
                }
                continue
            } else if current() == "}" {
                advance()
                return .object(pairs)
            } else if current() == nil {
                throw error(
                    "Unterminated object — missing closing '}'",
                    suggestion: "Add a closing '}'."
                )
            } else {
                throw error(
                    "Expected ',' or '}' after value",
                    suggestion: "Add a comma to separate properties, or close the object with '}'."
                )
            }
        }
    }

    private func parseArray() throws -> JSONNode {
        depth += 1
        defer { depth -= 1 }
        if depth > maxDepth {
            throw error("JSON is nested too deeply (over \(maxDepth) levels)", suggestion: "This is likely malformed or an extreme edge case rather than real data.")
        }
        advance() // consume '['
        try skipWhitespaceAndComments()
        var items: [JSONNode] = []

        if current() == "]" { advance(); return .array(items) }

        while true {
            try skipWhitespaceAndComments()
            let value = try parseValue()
            items.append(value)
            try skipWhitespaceAndComments()

            if current() == "," {
                advance()
                try skipWhitespaceAndComments()
                if current() == "]" {
                    if lenient {
                        advance()
                        recordFix("Removed trailing comma before ']'")
                        return .array(items)
                    } else {
                        throw error(
                            "Trailing comma is not allowed before ']'",
                            suggestion: "Remove the comma after the last item."
                        )
                    }
                }
                continue
            } else if current() == "]" {
                advance()
                return .array(items)
            } else if current() == nil {
                throw error(
                    "Unterminated array — missing closing ']'",
                    suggestion: "Add a closing ']'."
                )
            } else {
                throw error(
                    "Expected ',' or ']' after item",
                    suggestion: "Add a comma to separate items, or close the array with ']'."
                )
            }
        }
    }

    private func parseKey() throws -> String {
        guard let c = current() else {
            throw error("Expected an object key", suggestion: "Add a quoted key, e.g. \"name\".")
        }
        if c == "\"" {
            return try parseQuotedString(delimiter: "\"")
        }
        if c == "'" {
            if lenient {
                let s = try parseQuotedString(delimiter: "'")
                recordFix("Converted single-quoted key to double quotes")
                return s
            } else {
                throw error(
                    "Object keys must be double-quoted strings",
                    suggestion: "Wrap the key in double quotes."
                )
            }
        }
        if lenient, let ident = tryParseIdentifier() {
            recordFix("Added double quotes around unquoted key '\(ident)'")
            return ident
        }
        throw error(
            "Expected a double-quoted string as the object key",
            suggestion: "Wrap the key in double quotes, e.g. \"key\": value."
        )
    }

    private func tryParseIdentifier() -> String? {
        guard let c = current(), c.isLetter || c == "_" || c == "$" else { return nil }
        var result = String(c)
        advance()
        while let c2 = current(), c2.isLetter || c2.isNumber || c2 == "_" || c2 == "$" {
            result.append(c2)
            advance()
        }
        return result
    }

    // MARK: - Strings

    private func parseQuotedString(delimiter: Character) throws -> String {
        let startLine = line
        let startCol = col
        advance() // consume opening delimiter
        var result = ""

        while true {
            guard let c = current() else {
                throw JSONParseError(
                    message: "Unterminated string literal",
                    suggestion: "Add a closing \(delimiter) to end the string.",
                    line: startLine,
                    column: startCol
                )
            }
            if c == delimiter {
                advance()
                return result
            }
            if c == "\\" {
                advance()
                guard let esc = current() else {
                    throw error("Unterminated escape sequence")
                }
                switch esc {
                case "\"": result.append("\""); advance()
                case "\\": result.append("\\"); advance()
                case "/": result.append("/"); advance()
                case "n": result.append("\n"); advance()
                case "t": result.append("\t"); advance()
                case "r": result.append("\r"); advance()
                case "b": result.append("\u{08}"); advance()
                case "f": result.append("\u{0C}"); advance()
                case "'": result.append("'"); advance()
                case "u":
                    advance()
                    let high = try readFourHexDigits()
                    if (0xD800...0xDBFF).contains(high) {
                        // High surrogate: it must be followed by a matching low
                        // surrogate \u escape, and the pair combines into one
                        // scalar (e.g. 😀 -> 😀). A plain
                        // Unicode.Scalar(high) is invalid on its own.
                        let savedPos = pos, savedLine = line, savedCol = col
                        if current() == "\\" && peek(1) == "u" {
                            advance(); advance()
                            let low = try readFourHexDigits()
                            if (0xDC00...0xDFFF).contains(low) {
                                let combined = 0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)
                                if let scalar = Unicode.Scalar(combined) {
                                    result.append(Character(scalar))
                                }
                            } else {
                                pos = savedPos; line = savedLine; col = savedCol
                                try handleLoneSurrogate(high)
                            }
                        } else {
                            try handleLoneSurrogate(high)
                        }
                    } else if (0xDC00...0xDFFF).contains(high) {
                        try handleLoneSurrogate(high)
                    } else if let scalar = Unicode.Scalar(high) {
                        result.append(Character(scalar))
                    }
                default:
                    if lenient {
                        recordFix("Kept literal character after unnecessary '\\' escape")
                        result.append(esc)
                        advance()
                    } else {
                        throw error(
                            "Invalid escape sequence '\\\(esc)'",
                            suggestion: "Use a valid escape: \\n \\t \\r \\b \\f \\\" \\\\ \\/ or \\uXXXX."
                        )
                    }
                }
                continue
            }
            if let scalar = c.unicodeScalars.first, scalar.value < 0x20 {
                if lenient && c == "\n" {
                    recordFix("Escaped a raw newline inside a string")
                    result.append("\\n")
                    advance()
                    continue
                }
                throw error(
                    "Control character in string must be escaped",
                    suggestion: "Escape it, e.g. as \\n or \\t."
                )
            }
            result.append(c)
            advance()
        }
    }

    private func readFourHexDigits() throws -> UInt32 {
        var hex = ""
        for _ in 0..<4 {
            guard let h = current(), h.isHexDigit else {
                throw error("Invalid \\u escape — expected 4 hex digits")
            }
            hex.append(h)
            advance()
        }
        guard let value = UInt32(hex, radix: 16) else {
            throw error("Invalid \\u escape — expected 4 hex digits")
        }
        return value
    }

    private func handleLoneSurrogate(_ value: UInt32) throws {
        let hex = String(format: "%04x", value)
        if lenient {
            recordFix("Dropped invalid lone UTF-16 surrogate \\u\(hex) (no matching pair)")
        } else {
            throw error(
                "'\\u\(hex)' is a lone UTF-16 surrogate with no matching pair",
                suggestion: "Surrogate pairs must appear together, e.g. \\uD83D\\uDE00 for 😀."
            )
        }
    }

    // MARK: - Numbers

    private func parseNumber() throws -> JSONNode {
        let startLine = line
        let startCol = col
        var raw = ""
        let allowed: Set<Character> = ["+", "-", ".", "e", "E", "0","1","2","3","4","5","6","7","8","9"]
        while let c = current(), allowed.contains(c) {
            raw.append(c)
            advance()
        }
        if raw.isEmpty {
            throw JSONParseError(message: "Expected a number", suggestion: nil, line: startLine, column: startCol)
        }

        let strictPattern = #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#
        if raw.range(of: strictPattern, options: .regularExpression) != nil {
            return .number(raw)
        }

        if lenient {
            var fixed = raw
            var notes: [String] = []
            if fixed.hasPrefix("+") {
                fixed.removeFirst()
                notes.append("removed unnecessary leading '+'")
            }
            if fixed.hasPrefix(".") {
                fixed = "0" + fixed
                notes.append("added missing leading 0 before '.'")
            }
            if fixed.hasPrefix("-.") {
                fixed = "-0" + fixed.dropFirst()
                notes.append("added missing leading 0 before '.'")
            }
            if fixed.hasSuffix(".") {
                fixed += "0"
                notes.append("added missing digit after '.'")
            }
            // Strip extra leading zeros: "007" -> "7", "-007" -> "-7"
            let negative = fixed.hasPrefix("-")
            var digitsPart = negative ? String(fixed.dropFirst()) : fixed
            if digitsPart.count > 1 {
                let intPart = digitsPart.prefix(while: { $0.isNumber })
                if intPart.count > 1 && intPart.first == "0" {
                    let trimmed = intPart.drop(while: { $0 == "0" })
                    let newIntPart = trimmed.isEmpty ? "0" : String(trimmed)
                    digitsPart = newIntPart + digitsPart.dropFirst(intPart.count)
                    notes.append("removed leading zeros")
                }
            }
            fixed = (negative ? "-" : "") + digitsPart

            if fixed.range(of: strictPattern, options: .regularExpression) != nil {
                for n in notes { recordFix("Fixed number '\(raw)': \(n)") }
                return .number(fixed)
            }
            if Double(raw) != nil {
                // Fall back to accepting it loosely rather than failing the whole document.
                return .number(raw)
            }
        }

        var suggestion = "Numbers must look like 123, -4.5, or 6.02e23."
        if raw.hasPrefix(".") || raw.hasPrefix("-.") {
            suggestion = "Add a leading 0 before the decimal point, e.g. '0\(raw)'."
        } else if raw.hasPrefix("+") {
            suggestion = "Remove the leading '+' — JSON numbers can't have one."
        } else if raw.count > 1 && (raw.first == "0" || (raw.hasPrefix("-0") && raw.count > 2 && raw[raw.index(raw.startIndex, offsetBy: 2)].isNumber)) {
            suggestion = "Remove the leading zero(s)."
        }
        throw JSONParseError(
            message: "Invalid number literal '\(raw)'",
            suggestion: suggestion,
            line: startLine,
            column: startCol
        )
    }
}
