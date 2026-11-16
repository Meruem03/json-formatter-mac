import SwiftUI
import AppKit
import JSONCore

enum StatusKind {
    case none, success, error
}

struct ContentView: View {
    @State private var inputText: String = ContentView.sampleInput
    @State private var outputText: String = ""
    @State private var indentWidth: Int = 2

    @State private var statusKind: StatusKind = .none
    @State private var statusTitle: String = ""
    @State private var statusDetail: String = ""
    @State private var fixNotes: [String] = []

    static let sampleInput = """
    {
      name: 'Ilia',
      "age": 29,
      "active": True,
      "tags": ["swift", "macos",],
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            buttonRow
            if statusKind != .none {
                statusView
            }
            if !fixNotes.isEmpty {
                fixesView
            }
            HSplitView {
                editorPane(title: "Input", text: $inputText)
                editorPane(title: "Output", text: $outputText)
            }
        }
        .padding()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("JSON Formatter")
                .font(.title2).bold()
            Spacer()
            Picker("Indent", selection: $indentWidth) {
                Text("2 spaces").tag(2)
                Text("4 spaces").tag(4)
                Text("Compact").tag(0)
            }
            .frame(width: 180)
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack(spacing: 10) {
            Button("Validate", action: runValidate)
            Button("Format", action: runFormat)
            Button("Auto-Fix", action: runAutoFix)
                .keyboardShortcut(.defaultAction)
            Divider().frame(height: 18)
            Button("Flatten", action: runFlatten)
            Button("Unflatten", action: runUnflatten)
            Spacer()
            Button("Use Output as Input", action: useOutputAsInput)
                .disabled(outputText.isEmpty)
            Button("Copy Output", action: copyOutput)
                .disabled(outputText.isEmpty)
        }
    }

    // MARK: - Status

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(.headline)
                .foregroundColor(statusKind == .success ? .green : .red)
            if !statusDetail.isEmpty {
                Text(statusDetail)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((statusKind == .success ? Color.green : Color.red).opacity(0.1))
        .cornerRadius(8)
    }

    private var fixesView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Fixes applied (\(fixNotes.count)):")
                .font(.subheadline).bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(fixNotes.enumerated()), id: \.offset) { _, note in
                        Text("• \(note)")
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Editors

    private func editorPane(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .border(Color.gray.opacity(0.3))
        }
        .frame(minWidth: 400)
    }

    // MARK: - Actions

    private func runValidate() {
        fixNotes = []
        do {
            _ = try JSONParser(inputText, lenient: false).parse()
            statusKind = .success
            statusTitle = "✓ Valid JSON"
            statusDetail = ""
        } catch let e as JSONParseError {
            showParseError(e)
        } catch {
            showGenericError(error)
        }
    }

    private func runFormat() {
        fixNotes = []
        do {
            let node = try JSONParser(inputText, lenient: false).parse()
            outputText = JSONSerializer.serialize(node, indentWidth: indentWidth)
            statusKind = .success
            statusTitle = "✓ Formatted"
            statusDetail = ""
        } catch let e as JSONParseError {
            showParseError(e)
        } catch {
            showGenericError(error)
        }
    }

    private func runAutoFix() {
        let parser = JSONParser(inputText, lenient: true)
        do {
            let node = try parser.parse()
            outputText = JSONSerializer.serialize(node, indentWidth: indentWidth)
            fixNotes = parser.fixes.map { "Line \($0.line), Col \($0.column): \($0.message)" }
            statusKind = .success
            statusTitle = fixNotes.isEmpty ? "✓ No issues found" : "✓ Fixed \(fixNotes.count) issue(s)"
            statusDetail = ""
        } catch let e as JSONParseError {
            fixNotes = parser.fixes.map { "Line \($0.line), Col \($0.column): \($0.message)" }
            showParseError(e, prefix: "Couldn't fully auto-fix — one problem needs a manual change:\n")
        } catch {
            showGenericError(error)
        }
    }

    private func runFlatten() {
        fixNotes = []
        do {
            let node = try JSONParser(inputText, lenient: false).parse()
            let flat = JSONFlatten.flatten(node)
            outputText = JSONSerializer.serialize(flat, indentWidth: indentWidth)
            statusKind = .success
            statusTitle = "✓ Flattened"
            statusDetail = ""
        } catch let e as JSONParseError {
            showParseError(e, prefix: "Fix this first, then Flatten:\n")
        } catch {
            showGenericError(error)
        }
    }

    private func runUnflatten() {
        fixNotes = []
        do {
            let node = try JSONParser(inputText, lenient: false).parse()
            let nested = JSONFlatten.unflatten(node)
            outputText = JSONSerializer.serialize(nested, indentWidth: indentWidth)
            statusKind = .success
            statusTitle = "✓ Unflattened"
            statusDetail = ""
        } catch let e as JSONParseError {
            showParseError(e, prefix: "Fix this first, then Unflatten:\n")
        } catch {
            showGenericError(error)
        }
    }

    private func useOutputAsInput() {
        inputText = outputText
        statusKind = .none
        fixNotes = []
    }

    private func copyOutput() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputText, forType: .string)
    }

    // MARK: - Error presentation

    private func showParseError(_ e: JSONParseError, prefix: String = "") {
        statusKind = .error
        statusTitle = "✗ Problem at line \(e.line), column \(e.column)"
        var detail = prefix + e.message
        if let suggestion = e.suggestion {
            detail += "\nFix: \(suggestion)"
        }
        detail += "\n\n" + errorSnippet(line: e.line, column: e.column)
        statusDetail = detail
    }

    private func showGenericError(_ error: Error) {
        statusKind = .error
        statusTitle = "✗ Error"
        statusDetail = error.localizedDescription
    }

    private func errorSnippet(line: Int, column: Int) -> String {
        let lines = inputText.components(separatedBy: "\n")
        guard line - 1 >= 0, line - 1 < lines.count else { return "" }
        let lineText = lines[line - 1]
        let caretCount = max(0, column - 1)
        let caretLine = String(repeating: " ", count: caretCount) + "^"
        return lineText + "\n" + caretLine
    }
}

#Preview {
    ContentView()
}
