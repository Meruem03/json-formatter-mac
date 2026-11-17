import Foundation
import JSONCore

var failures = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

// 1. Valid JSON passes strict parse.
do {
    let text = "{\"a\": 1, \"b\": [1,2,3]}"
    _ = try JSONParser(text, lenient: false).parse()
    check("valid JSON parses strictly", true)
} catch {
    check("valid JSON parses strictly", false)
}

// 2. Trailing comma is rejected strictly, with a location.
do {
    let text = "{\"a\": 1,}"
    _ = try JSONParser(text, lenient: false).parse()
    check("trailing comma rejected", false)
} catch let e as JSONParseError {
    check("trailing comma rejected", e.line == 1 && e.message.lowercased().contains("trailing comma"))
} catch {
    check("trailing comma rejected", false)
}

// 3. Missing comma between properties is reported on the right line/column.
do {
    let text = "{\n  \"a\": 1\n  \"b\": 2\n}"
    _ = try JSONParser(text, lenient: false).parse()
    check("missing comma rejected", false)
} catch let e as JSONParseError {
    check("missing comma rejected", e.line == 3)
} catch {
    check("missing comma rejected", false)
}

// 4. Auto-fix repairs trailing commas, single quotes, unquoted keys, Python literals.
do {
    let text = "{ name: 'Ilia', \"age\": 29, \"active\": True, \"tags\": [\"a\", \"b\",], }"
    let parser = JSONParser(text, lenient: true)
    let node = try parser.parse()
    let out = JSONSerializer.serialize(node, indentWidth: 2)
    check("auto-fix produces valid JSON", (try? JSONParser(out, lenient: false).parse()) != nil)
    check("auto-fix recorded fixes", parser.fixes.count >= 4)
    check("auto-fix quoted the key", out.contains("\"name\": \"Ilia\""))
    check("auto-fix kept true literal", out.contains("\"active\": true"))
} catch {
    check("auto-fix path threw unexpectedly: \(error)", false)
}

// 5. Flatten turns nested structures into dotted-path keys.
do {
    let text = "{\"user\":{\"name\":\"Ilia\",\"tags\":[\"a\",\"b\"]},\"count\":2}"
    let node = try JSONParser(text, lenient: false).parse()
    let flat = JSONFlatten.flatten(node)
    let out = JSONSerializer.serialize(flat, indentWidth: 0)
    check("flatten produces dotted keys", out.contains("\"user.name\":\"Ilia\"") && out.contains("\"user.tags.0\":\"a\""))
} catch {
    check("flatten threw unexpectedly: \(error)", false)
}

// 6. Unflatten reverses flatten exactly (round trip).
do {
    let text = "{\"user\":{\"name\":\"Ilia\",\"tags\":[\"a\",\"b\"]},\"count\":2}"
    let original = try JSONParser(text, lenient: false).parse()
    let flat = JSONFlatten.flatten(original)
    let rebuilt = JSONFlatten.unflatten(flat)
    let originalOut = JSONSerializer.serialize(original, indentWidth: 0)
    let rebuiltOut = JSONSerializer.serialize(rebuilt, indentWidth: 0)
    check("flatten -> unflatten round-trips", originalOut == rebuiltOut)
} catch {
    check("round-trip threw unexpectedly: \(error)", false)
}

// 7. Surrogate pairs decode to the correct character (regression: used to
//    silently drop astral-plane characters like emoji).
do {
    let text = "[\"\\uD83D\\uDE00\"]"
    let node = try JSONParser(text, lenient: false).parse()
    if case .array(let items) = node, case .string(let s) = items.first {
        check("surrogate pair decodes to emoji", s == "😀")
    } else {
        check("surrogate pair decodes to emoji", false)
    }
} catch {
    check("surrogate pair decodes to emoji: threw \(error)", false)
}

// 8. A lone (unpaired) surrogate is a clear strict error, not silent data loss.
do {
    let text = "[\"\\uD83Dnotalow\"]"
    _ = try JSONParser(text, lenient: false).parse()
    check("lone surrogate rejected strictly", false)
} catch let e as JSONParseError {
    check("lone surrogate rejected strictly", e.message.contains("surrogate"))
} catch {
    check("lone surrogate rejected strictly", false)
}

// 9. Deeply nested JSON reports a clean error instead of crashing.
do {
    let text = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
    _ = try JSONParser(text, lenient: false).parse()
    check("extreme nesting rejected", false)
} catch let e as JSONParseError {
    check("extreme nesting rejected", e.message.contains("nested too deeply"))
} catch {
    check("extreme nesting rejected", false)
}

// 10. Deep merge: overlay fills in a new key, overrides a matching nested
//    key, and replaces an array outright, while leaving untouched keys be.
do {
    let settings = """
    {"ConnectionStrings":{"Default":"Server=prod"},"Logging":{"Level":"Info"},"Tags":["a","b"]}
    """
    let secrets = """
    {"ConnectionStrings":{"Default":"Server=prod;Password=xxx","Backup":"Server=dr"},"Tags":["c"]}
    """
    let baseNode = try JSONParser(settings, lenient: false).parse()
    let overlayNode = try JSONParser(secrets, lenient: false).parse()
    let merged = JSONMerge.merge(base: baseNode, overlay: overlayNode)
    let out = JSONSerializer.serialize(merged, indentWidth: 0)
    check("merge overrides a matching nested key", out.contains("\"Default\":\"Server=prod;Password=xxx\""))
    check("merge appends a new nested key", out.contains("\"Backup\":\"Server=dr\""))
    check("merge keeps an untouched key", out.contains("\"Logging\":{\"Level\":\"Info\"}"))
    check("merge replaces an array outright", out.contains("\"Tags\":[\"c\"]") && !out.contains("\"a\""))
} catch {
    check("deep merge threw unexpectedly: \(error)", false)
}

// 11. A zero-width space pasted in from somewhere else (right after the
//    opening brace, exactly like a real clipboard paste can produce) used
//    to make the parser miscount and report a confusing "expected object
//    key" error. Strict mode should now name the invisible character
//    specifically; lenient mode should just strip it and say so.
do {
    let text = "{\u{200B}\n  \"a\": 1\n}"
    _ = try JSONParser(text, lenient: false).parse()
    check("invisible whitespace rejected strictly with a clear message", false)
} catch let e as JSONParseError {
    check("invisible whitespace rejected strictly with a clear message", e.message.contains("invisible character") && e.message.contains("U+200B"))
} catch {
    check("invisible whitespace rejected strictly with a clear message", false)
}
do {
    let text = "{\u{200B}\n  \"a\": 1\n}"
    let parser = JSONParser(text, lenient: true)
    let node = try parser.parse()
    let out = JSONSerializer.serialize(node, indentWidth: 0)
    check("invisible whitespace auto-fixed", out == "{\"a\":1}")
    check("invisible whitespace auto-fix was logged", parser.fixes.contains { $0.message.contains("invisible") })
} catch {
    check("invisible whitespace auto-fix threw unexpectedly: \(error)", false)
}

// 12. Windows-style CRLF line endings (very common in pasted .NET config
//    files) used to fail entirely: Swift's Character treats "\r\n" as one
//    grapheme cluster that equals neither "\n" nor "\r", so it was never
//    recognized as whitespace, and every line was miscounted as line 1.
do {
    let text = "{\r\n  \"a\": 1,\r\n  \"b\": {\r\n    \"c\": 2\r\n  }\r\n}\r\n"
    let node = try JSONParser(text, lenient: false).parse()
    let out = JSONSerializer.serialize(node, indentWidth: 0)
    check("CRLF line endings parse as valid JSON", out == "{\"a\":1,\"b\":{\"c\":2}}")
} catch {
    check("CRLF line endings parse as valid JSON: threw \(error)", false)
}
do {
    // A real error on a CRLF document should still report the correct
    // line number, not be stuck at line 1 for the whole file.
    let text = "{\r\n  \"a\": 1\r\n  \"b\": 2\r\n}"
    _ = try JSONParser(text, lenient: false).parse()
    check("CRLF line numbers stay accurate on error", false)
} catch let e as JSONParseError {
    check("CRLF line numbers stay accurate on error", e.line == 3)
} catch {
    check("CRLF line numbers stay accurate on error", false)
}

// 13. Auto-Fix strips // and /* */ comments correctly in every position
//    (leading, trailing, between properties, inside arrays, adjacent to
//    trailing commas, combined with CRLF line endings, no space before
//    the slashes, no trailing newline at EOF).
let commentCases: [(String, String, String)] = [
    ("leading comment", "// top comment\n{\"a\": 1}", "{\"a\":1}"),
    ("trailing comment after value", "{\"a\": 1} // trailing", "{\"a\":1}"),
    ("comment before value", "{\"a\": // comment\n1}", "{\"a\":1}"),
    ("comment between props", "{\"a\": 1, // c1\n\"b\": 2}", "{\"a\":1,\"b\":2}"),
    ("comment inside array", "[1, // c1\n2]", "[1,2]"),
    ("comment with no trailing newline at EOF", "{\"a\": 1} //trailing no newline", "{\"a\":1}"),
    ("block comment", "{/* c */\"a\": 1}", "{\"a\":1}"),
    ("comment with no space before //", "{\"a\": 1}// no space", "{\"a\":1}"),
]
for (name, text, expected) in commentCases {
    do {
        let node = try JSONParser(text, lenient: true).parse()
        check("auto-fix handles: \(name)", JSONSerializer.serialize(node, indentWidth: 0) == expected)
    } catch {
        check("auto-fix handles: \(name) (threw \(error))", false)
    }
}

// 14. In strict mode, a comment should be named specifically as the
//    problem rather than producing an unrelated generic error.
do {
    _ = try JSONParser("{\"a\": 1} // trailing", lenient: false).parse()
    check("strict mode names a // comment as the problem", false)
} catch let e as JSONParseError {
    check("strict mode names a // comment as the problem", e.message.contains("comment"))
} catch {
    check("strict mode names a // comment as the problem", false)
}

// 15. Comments combined with CRLF line endings and a trailing comma (the
//    shape of a real-world Windows/.NET config file with notes added).
do {
    let text = "{\r\n  \"Settings\": { // settings block\r\n    \"BatchSize\": \"500\", // batch size\r\n  },\r\n  \"Other\": 1 // trailing\r\n}"
    let node = try JSONParser(text, lenient: true).parse()
    let out = JSONSerializer.serialize(node, indentWidth: 0)
    check("comments + CRLF + trailing comma all auto-fix together", out == "{\"Settings\":{\"BatchSize\":\"500\"},\"Other\":1}")
} catch {
    check("comments + CRLF + trailing comma threw unexpectedly: \(error)", false)
}

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
