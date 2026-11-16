import SwiftUI
import AppKit

/// A plain-text NSTextView wrapped for SwiftUI, with a line-number gutter
/// and basic JSON syntax highlighting. SwiftUI's TextEditor has neither,
/// and also silently applies smart-quote/dash substitution on macOS, which
/// is actively harmful for editing JSON (a "smart" quote isn't valid JSON).
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = true
        textView.allowsUndo = true

        // This is a code editor, not prose: none of these "helpful"
        // substitutions are welcome in JSON.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.font = Self.font
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 6, height: 8)

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        // Register the highlighter before setting initial text so the
        // first load gets colored too, not just subsequent edits.
        textView.textStorage?.delegate = context.coordinator
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            if let storage = textView.textStorage {
                JSONSyntaxHighlighter.highlight(storage)
            }
            (scrollView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        private let text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if text.wrappedValue != tv.string {
                text.wrappedValue = tv.string
            }
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            JSONSyntaxHighlighter.highlight(textStorage)
        }
    }
}

/// Minimal regex-based JSON highlighter. Re-colors the whole document on
/// each edit — fine for the document sizes a formatter tool actually sees;
/// large multi-MB files would want incremental highlighting instead.
enum JSONSyntaxHighlighter {
    private static let keyRegex = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\])*"(?=\s*:)"#)
    private static let stringRegex = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#)
    private static let numberRegex = try! NSRegularExpression(pattern: #"(?<![\w"])-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?(?![\w"])"#)
    private static let keywordRegex = try! NSRegularExpression(pattern: #"\b(?:true|false|null)\b"#)
    private static let punctuationRegex = try! NSRegularExpression(pattern: #"[\{\}\[\]:,]"#)

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static let punctuationColor = NSColor.secondaryLabelColor
    private static let stringColor = adaptive(
        light: NSColor(calibratedRed: 0.70, green: 0.18, blue: 0.18, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.47, alpha: 1)
    )
    private static let keyColor = adaptive(
        light: NSColor(calibratedRed: 0.00, green: 0.30, blue: 0.60, alpha: 1),
        dark: NSColor(calibratedRed: 0.45, green: 0.68, blue: 1.00, alpha: 1)
    )
    private static let numberColor = adaptive(
        light: NSColor(calibratedRed: 0.00, green: 0.45, blue: 0.10, alpha: 1),
        dark: NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.50, alpha: 1)
    )
    private static let keywordColor = adaptive(
        light: NSColor(calibratedRed: 0.50, green: 0.00, blue: 0.55, alpha: 1),
        dark: NSColor(calibratedRed: 0.78, green: 0.55, blue: 1.00, alpha: 1)
    )

    static func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string as NSString

        storage.beginEditing()
        storage.setAttributes([.font: CodeEditor.font, .foregroundColor: NSColor.labelColor], range: full)

        apply(punctuationRegex, in: text, full: full, storage: storage, color: punctuationColor)
        apply(stringRegex, in: text, full: full, storage: storage, color: stringColor)
        apply(keyRegex, in: text, full: full, storage: storage, color: keyColor, bold: true)
        apply(numberRegex, in: text, full: full, storage: storage, color: numberColor)
        apply(keywordRegex, in: text, full: full, storage: storage, color: keywordColor, bold: true)

        storage.endEditing()
    }

    private static func apply(
        _ regex: NSRegularExpression,
        in text: NSString,
        full: NSRange,
        storage: NSTextStorage,
        color: NSColor,
        bold: Bool = false
    ) {
        regex.enumerateMatches(in: text as String, options: [], range: full) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: color, range: r)
            if bold {
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: r)
            }
        }
    }
}

/// Classic NSRulerView-based line-number gutter for an NSTextView.
final class LineNumberRulerView: NSRulerView {
    private weak var codeTextView: NSTextView?

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.codeTextView = textView
        self.clientView = textView
        self.ruleThickness = 40

        NotificationCenter.default.addObserver(
            self, selector: #selector(contentDidChange),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentDidChange),
            name: NSView.frameDidChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentDidChange),
            name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func contentDidChange(_ note: Notification) {
        needsDisplay = true
    }

    private var lineNumberAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = codeTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView
        else { return }

        NSColor.textBackgroundColor.setFill()
        rect.fill()

        let visibleRect = scrollView.contentView.bounds
        let textInset = textView.textContainerInset
        let fullText = textView.string as NSString

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        if charRange.location > 0 {
            var linesBefore = 0
            fullText.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location), options: .byLines) { _, _, _, _ in
                linesBefore += 1
            }
            lineNumber = linesBefore + 1
        }

        var index = charRange.location
        let attrs = lineNumberAttributes

        while index < NSMaxRange(charRange) {
            let lineRange = fullText.lineRange(for: NSRange(location: index, length: 0))
            let glyphRangeForLine = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRangeForLine, in: textContainer)

            let yInTextView = lineRect.origin.y + textInset.height
            let yInRuler = yInTextView - visibleRect.origin.y

            let numberString = "\(lineNumber)" as NSString
            let size = numberString.size(withAttributes: attrs)
            let drawRect = NSRect(
                x: ruleThickness - size.width - 8,
                y: yInRuler + (lineRect.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            numberString.draw(in: drawRect, withAttributes: attrs)

            if NSMaxRange(lineRange) <= index {
                break // safety net against an infinite loop on malformed ranges
            }
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }

        // If the document is empty or ends with a newline, there's a final
        // empty logical line the loop above never reaches; draw its number.
        if fullText.length == 0 || fullText.hasSuffix("\n") {
            let glyphRangeForEnd = layoutManager.glyphRange(forCharacterRange: NSRange(location: fullText.length, length: 0), actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRangeForEnd, in: textContainer)
            let yInTextView = lineRect.origin.y + textInset.height
            let yInRuler = yInTextView - visibleRect.origin.y
            let numberString = "\(lineNumber)" as NSString
            let size = numberString.size(withAttributes: attrs)
            let drawRect = NSRect(
                x: ruleThickness - size.width - 8,
                y: yInRuler,
                width: size.width,
                height: max(size.height, 14)
            )
            numberString.draw(in: drawRect, withAttributes: attrs)
        }
    }
}
