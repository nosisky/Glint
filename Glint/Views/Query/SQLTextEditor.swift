//
//  SQLTextEditor.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI
import AppKit

// MARK: - Public Interface

/// A production-grade SQL editor with syntax highlighting, line numbers, and autocomplete.
/// Uses a custom gutter view instead of NSRulerView to avoid the separator line artifact.
struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onExecute: () -> Void
    var completionSource: AutocompleteSource

    struct AutocompleteSource: Equatable {
        var keywords: [String]
        var tableNames: [String]
        var columnNames: [String]
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SQLEditorContainer {
        let container = SQLEditorContainer(coordinator: context.coordinator)
        container.textView.string = text
        context.coordinator.applyHighlighting()
        return container
    }

    func updateNSView(_ container: SQLEditorContainer, context: Context) {
        let coordinator = context.coordinator
        coordinator.completionSource = completionSource
        coordinator.onExecute = onExecute
        container.textView.executeHandler = onExecute

        // Only update if text changed externally (e.g. from history recall)
        if container.textView.string != text {
            container.textView.string = text
            let endPos = (text as NSString).length
            container.textView.setSelectedRange(NSRange(location: endPos, length: 0))
            coordinator.applyHighlighting()
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLTextEditor
        weak var textView: SQLNSTextView?
        weak var gutterView: LineGutterView?
        var completionSource: AutocompleteSource
        var onExecute: () -> Void

        private var isUpdating = false
        private var highlightDebounce: DispatchWorkItem?

        // Pre-compiled regexes (static = one-time cost)
        private static let patterns: [(NSRegularExpression, NSColor, NSFont?)] = {
            let bold13 = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
            return [
                // Order matters: later rules override earlier ones for overlapping ranges.
                // Comments go last since they should override everything.
                (try! NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b"), .systemCyan, nil),
                (try! NSRegularExpression(pattern: "'(?:[^'\\\\]|\\\\.)*'"), .systemOrange, nil),
                (try! NSRegularExpression(
                    pattern: "\\b(uuid|integer|int|int2|int4|int8|smallint|bigint|serial|bigserial|boolean|bool|text|varchar|character varying|char|bpchar|date|time|timetz|timestamp|timestamptz|json|jsonb|numeric|decimal|real|float4|float8|double precision|bytea|inet|cidr|macaddr|money|xml|interval|oid|regclass|regtype)\\b",
                    options: .caseInsensitive), .systemBlue, nil),
                (try! NSRegularExpression(
                    pattern: "\\b(now|current_timestamp|current_date|current_time|gen_random_uuid|uuid_generate_v4|count|sum|avg|min|max|coalesce|nullif|greatest|least|array_agg|string_agg|row_number|rank|dense_rank|lag|lead|first_value|last_value|ntile|length|upper|lower|trim|substring|replace|concat|position|regexp_replace|regexp_matches|to_char|to_date|to_timestamp|to_number|extract|date_part|date_trunc|age|clock_timestamp|pg_sleep)\\s*\\(",
                    options: .caseInsensitive), .systemTeal, nil),
                (try! NSRegularExpression(
                    pattern: "\\b(SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|DROP|ALTER|ADD|INDEX|UNIQUE|PRIMARY|KEY|FOREIGN|REFERENCES|NOT|NULL|DEFAULT|CONSTRAINT|AND|OR|AS|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|FULL|ON|USING|GROUP BY|ORDER BY|ASC|DESC|LIMIT|OFFSET|HAVING|DISTINCT|CASE|WHEN|THEN|ELSE|END|IN|EXISTS|BETWEEN|LIKE|ILIKE|IS|BEGIN|COMMIT|ROLLBACK|GRANT|REVOKE|WITH|RETURNING|CASCADE|RESTRICT|IF|REPLACE|VIEW|FUNCTION|TRIGGER|SCHEMA|DATABASE|EXPLAIN|ANALYZE|VACUUM|TRUNCATE|UNION|ALL|INTERSECT|EXCEPT|FETCH|NEXT|ROWS|ONLY|FOR|CAST|LATERAL|RECURSIVE|MATERIALIZED|CONCURRENTLY|TEMPORARY|TEMP|TRUE|FALSE|COALESCE)\\b",
                    options: .caseInsensitive), .systemPurple, bold13),
                (try! NSRegularExpression(pattern: "--[^\\n]*"), .secondaryLabelColor, nil),
                (try! NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/"), .secondaryLabelColor, nil),
            ]
        }()

        init(_ parent: SQLTextEditor) {
            self.parent = parent
            self.completionSource = parent.completionSource
            self.onExecute = parent.onExecute
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string

            // Debounced highlighting (one frame delay)
            highlightDebounce?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.applyHighlighting() }
            highlightDebounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: item)
        }

        func applyHighlighting() {
            guard let textView, let textStorage = textView.textStorage else { return }
            isUpdating = true
            defer { isUpdating = false }

            let src = textStorage.string
            guard !src.isEmpty else {
                gutterView?.needsDisplay = true
                return
            }
            let fullRange = NSRange(location: 0, length: src.utf16.count)
            let defaultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

            textStorage.beginEditing()
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            textStorage.addAttribute(.font, value: defaultFont, range: fullRange)

            for (regex, color, font) in Self.patterns {
                regex.enumerateMatches(in: src, range: fullRange) { match, _, _ in
                    guard let r = match?.range else { return }
                    textStorage.addAttribute(.foregroundColor, value: color, range: r)
                    if let font { textStorage.addAttribute(.font, value: font, range: r) }
                }
            }
            textStorage.endEditing()
            gutterView?.needsDisplay = true
        }

        // MARK: - Autocomplete (Escape / Ctrl+Space triggers)

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            guard charRange.length > 0 else { return [] }
            let partial = (textView.string as NSString).substring(with: charRange).lowercased()

            // Pre-filter: combine all sources, case-insensitive prefix match
            var results: [String] = []
            for kw in completionSource.keywords where kw.lowercased().hasPrefix(partial) { results.append(kw) }
            for tn in completionSource.tableNames where tn.lowercased().hasPrefix(partial) { results.append(tn) }
            for cn in completionSource.columnNames where cn.lowercased().hasPrefix(partial) { results.append(cn) }
            return Array(Set(results)).sorted()
        }
    }
}

// MARK: - Container View (Gutter + ScrollView, no NSRulerView)

/// A plain NSView that lays out a line-number gutter alongside the text scroll view.
/// This completely avoids NSRulerView and its built-in separator line.
final class SQLEditorContainer: NSView {
    let scrollView: NSScrollView
    let textView: SQLNSTextView
    let gutterView: LineGutterView

    private static let gutterWidth: CGFloat = 36

    init(coordinator: SQLTextEditor.Coordinator) {
        let tv = SQLNSTextView()
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 12, height: 10)
        tv.textContainer?.widthTracksTextView = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = NSColor.labelColor
        tv.backgroundColor = .clear
        tv.insertionPointColor = NSColor.labelColor
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.usesFindBar = true
        tv.delegate = coordinator

        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        sv.documentView = tv

        let gv = LineGutterView()
        gv.textView = tv

        self.scrollView = sv
        self.textView = tv
        self.gutterView = gv

        super.init(frame: .zero)

        addSubview(gv)
        addSubview(sv)

        coordinator.textView = tv
        coordinator.gutterView = gv
        tv.executeHandler = coordinator.onExecute

        // Listen for scroll position changes to redraw gutter
        NotificationCenter.default.addObserver(
            gv, selector: #selector(LineGutterView.setNeedsRedisplay),
            name: NSView.boundsDidChangeNotification,
            object: sv.contentView
        )
        NotificationCenter.default.addObserver(
            gv, selector: #selector(LineGutterView.setNeedsRedisplay),
            name: NSText.didChangeNotification,
            object: tv
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let gw = Self.gutterWidth
        gutterView.frame = NSRect(x: 0, y: 0, width: gw, height: bounds.height)
        scrollView.frame = NSRect(x: gw, y: 0, width: bounds.width - gw, height: bounds.height)
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}

// MARK: - Line Gutter (custom NSView, no NSRulerView)

/// Draws line numbers as a standalone NSView. No NSRulerView, no separator line.
final class LineGutterView: NSView {
    weak var textView: NSTextView?

    private let labelFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private lazy var labelAttrs: [NSAttributedString.Key: Any] = [
        .font: labelFont,
        .foregroundColor: NSColor.tertiaryLabelColor
    ]

    override var isFlipped: Bool { true }

    @objc func setNeedsRedisplay() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // Gutter background
        (NSColor.controlBackgroundColor.withAlphaComponent(0.4)).setFill()
        dirtyRect.fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let nsString = textView.string as NSString

        // Count lines before visible range
        var lineNumber = 1
        if nsString.length == 0 {
            drawLabel(1, y: textView.textContainerInset.height)
            return
        }

        let preLen = min(charRange.location, nsString.length)
        if preLen > 0 {
            nsString.enumerateSubstrings(in: NSRange(location: 0, length: preLen), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                lineNumber += 1
            }
        }

        // Draw visible line numbers
        nsString.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { [weak self] _, lineRange, _, _ in
            guard let self else { return }
            let gi = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var rect = layoutManager.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            rect.origin.y += textView.textContainerInset.height
            rect.origin.y -= visibleRect.origin.y

            self.drawLabel(lineNumber, y: rect.origin.y, lineHeight: rect.height)
            lineNumber += 1
        }
    }

    private func drawLabel(_ number: Int, y: CGFloat, lineHeight: CGFloat = 16) {
        let s = "\(number)" as NSString
        let size = s.size(withAttributes: labelAttrs)
        s.draw(at: NSPoint(
            x: bounds.width - size.width - 8,
            y: y + (lineHeight - size.height) / 2
        ), withAttributes: labelAttrs)
    }
}

// MARK: - Custom NSTextView

final class SQLNSTextView: NSTextView {
    var executeHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘⏎ — Execute query
        if flags == .command && event.keyCode == 36 {
            executeHandler?()
            return
        }
        // ⌘/ — Toggle line comment
        if flags == .command && event.charactersIgnoringModifiers == "/" {
            toggleLineComment()
            return
        }
        // Ctrl+Space — Trigger autocomplete
        if flags == .control && event.keyCode == 49 {
            complete(nil)
            return
        }
        super.keyDown(with: event)
    }

    private func toggleLineComment() {
        guard let textStorage else { return }
        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: selectedRange())
        let line = nsString.substring(with: lineRange)

        if line.trimmingCharacters(in: .whitespaces).hasPrefix("--") {
            if let dashRange = line.range(of: "-- ") ?? line.range(of: "--") {
                let nsR = NSRange(dashRange, in: line)
                textStorage.replaceCharacters(
                    in: NSRange(location: lineRange.location + nsR.location, length: nsR.length),
                    with: ""
                )
            }
        } else {
            textStorage.replaceCharacters(
                in: NSRange(location: lineRange.location, length: 0),
                with: "-- "
            )
        }
    }
}
