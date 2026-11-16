import Foundation

public enum JSONSerializer {
    /// Pretty-prints with the given indent width (spaces). indentWidth == 0
    /// produces a single-line, compact representation.
    public static func serialize(_ node: JSONNode, indentWidth: Int) -> String {
        if indentWidth == 0 {
            return serializeCompact(node)
        }
        var out = ""
        write(node, indentWidth: indentWidth, level: 0, into: &out)
        return out
    }

    private static func pad(_ level: Int, _ width: Int) -> String {
        String(repeating: " ", count: level * width)
    }

    private static func write(_ node: JSONNode, indentWidth: Int, level: Int, into out: inout String) {
        switch node {
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, pair) in pairs.enumerated() {
                out += pad(level + 1, indentWidth)
                out += escapeString(pair.0)
                out += ": "
                write(pair.1, indentWidth: indentWidth, level: level + 1, into: &out)
                if i < pairs.count - 1 { out += "," }
                out += "\n"
            }
            out += pad(level, indentWidth) + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad(level + 1, indentWidth)
                write(item, indentWidth: indentWidth, level: level + 1, into: &out)
                if i < items.count - 1 { out += "," }
                out += "\n"
            }
            out += pad(level, indentWidth) + "]"
        case .string(let s):
            out += escapeString(s)
        case .number(let n):
            out += n
        case .bool(let b):
            out += b ? "true" : "false"
        case .null:
            out += "null"
        }
    }

    private static func serializeCompact(_ node: JSONNode) -> String {
        switch node {
        case .object(let pairs):
            let body = pairs.map { "\(escapeString($0.0)):\(serializeCompact($0.1))" }.joined(separator: ",")
            return "{\(body)}"
        case .array(let items):
            let body = items.map { serializeCompact($0) }.joined(separator: ",")
            return "[\(body)]"
        case .string(let s):
            return escapeString(s)
        case .number(let n):
            return n
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        }
    }

    public static func escapeString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
