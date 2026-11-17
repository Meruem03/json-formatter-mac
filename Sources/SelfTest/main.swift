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

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
