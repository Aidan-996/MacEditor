import SwiftUI
import AppKit

struct CursorPosition: Equatable {
    var line: Int = 1
    var column: Int = 1
}

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var language: Language
    var theme: Theme
    var fontSize: CGFloat
    var tabWidth: Int
    var softWrap: Bool
    var showInvisibles: Bool
    var showIndentGuides: Bool
    /// Per-window state; the coordinator pushes cursor position and counts straight into it.
    var ui: EditorUIState

    static let lineHeightMultiple: CGFloat = 1.4

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let contentSize = scrollView.contentSize
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 4
        layoutManager.addTextContainer(container)

        let tv = CodeTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: container)
        tv.minSize = NSSize(width: 0, height: contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 12, height: 10)
        tv.drawsBackground = true
        tv.delegate = context.coordinator
        tv.string = text
        tv.showInvisibles = showInvisibles
        tv.showIndentGuides = showIndentGuides

        scrollView.documentView = tv
        let ruler = LineNumberRulerView(textView: tv, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let c = context.coordinator
        c.textView = tv
        c.scrollView = scrollView
        c.ruler = ruler
        c.applyAppearance(force: true)
        c.applyWrap(softWrap)
        c.highlightAll()
        tv.rebuildFolds()
        ui.textView = tv
        c.reportCursor()
        ui.updateCounts(text, immediate: true)
        ui.scheduleOutline(text, language: language, immediate: true)
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.hasMarkedText() { return }
        if tv.string != text {
            let selection = tv.selectedRange()
            tv.string = text
            c.undo.removeAllActions()
            let loc = min(selection.location, (text as NSString).length)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
            c.highlightAll()
            tv.rebuildFolds()
            c.reportCursor()
            ui.updateCounts(text)
            ui.scheduleOutline(text, language: language)
        }
        if tv.showInvisibles != showInvisibles || tv.showIndentGuides != showIndentGuides {
            tv.showInvisibles = showInvisibles
            tv.showIndentGuides = showIndentGuides
            tv.needsDisplay = true
        }
        if ui.textView !== tv { ui.textView = tv }
        c.applyAppearance(force: false)
        if c.lastWrap != softWrap { c.applyWrap(softWrap) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: CodeTextView?
        weak var scrollView: NSScrollView?
        weak var ruler: LineNumberRulerView?
        let undo = UndoManager()
        var lastWrap: Bool?
        private var lastFontSize: CGFloat = 0
        private var lastTabWidth = 0
        private var lastLanguage: Language?
        private var lastTheme: Theme?
        private var pendingHighlight: DispatchWorkItem?
        private var pendingFolds: DispatchWorkItem?
        private(set) var paragraph = NSParagraphStyle()

        init(_ parent: EditorTextView) { self.parent = parent }

        var font: NSFont { NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular) }

        func applyAppearance(force: Bool) {
            guard let tv = textView else { return }
            let changed = force || lastFontSize != parent.fontSize || lastTabWidth != parent.tabWidth
                || lastLanguage != parent.language || lastTheme != parent.theme
            guard changed else { return }
            lastFontSize = parent.fontSize
            lastTabWidth = parent.tabWidth
            lastLanguage = parent.language
            lastTheme = parent.theme
            let theme = parent.theme

            let f = font
            let charWidth = (" " as NSString).size(withAttributes: [.font: f]).width
            let style = NSMutableParagraphStyle()
            style.tabStops = []
            style.defaultTabInterval = charWidth * CGFloat(parent.tabWidth)
            style.lineHeightMultiple = EditorTextView.lineHeightMultiple
            paragraph = style

            tv.tabWidth = parent.tabWidth
            tv.commentStyle = CommentStyle.for(parent.language)
            tv.font = f
            tv.defaultParagraphStyle = style
            tv.backgroundColor = theme.ns(\.background)
            tv.insertionPointColor = theme.ns(\.cursor)
            tv.selectedTextAttributes = [.backgroundColor: theme.ns(\.selection)]
            tv.currentLineColor = theme.ns(\.currentLine)
            tv.bracketColor = theme.ns(\.bracket)
            tv.indentGuideColor = Theme.ns(theme.gutterText, alpha: 0.35)
            tv.invisibleColor = Theme.ns(theme.gutterText, alpha: 0.55)
            tv.typingAttributes = [.font: f, .foregroundColor: theme.ns(\.text), .paragraphStyle: style]
            scrollView?.backgroundColor = theme.ns(\.background)
            scrollView?.scrollerKnobStyle = theme.isDark ? .light : .dark
            ruler?.theme = theme

            if !force { highlightAll() }
            tv.needsDisplay = true
        }

        func applyWrap(_ wrap: Bool) {
            guard let tv = textView, let sv = scrollView, let tc = tv.textContainer else { return }
            lastWrap = wrap
            let big = CGFloat.greatestFiniteMagnitude
            if wrap {
                sv.hasHorizontalScroller = false
                tv.isHorizontallyResizable = false
                tc.widthTracksTextView = true
                tv.setFrameSize(NSSize(width: sv.contentSize.width, height: tv.frame.height))
            } else {
                sv.hasHorizontalScroller = true
                tv.isHorizontallyResizable = true
                tc.widthTracksTextView = false
                tc.containerSize = NSSize(width: big, height: big)
            }
            tv.layoutManager?.ensureLayout(for: tc)
            tv.needsDisplay = true
            ruler?.needsDisplay = true
        }

        func highlightAll() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            if tv.hasMarkedText() { return }
            Highlighter.highlight(storage, language: parent.language, theme: parent.theme, font: font, paragraph: paragraph)
            ruler?.needsDisplay = true
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            if tv.hasMarkedText() { return }
            parent.text = tv.string
            reportCursor()
            parent.ui.updateCounts(tv.string)
            parent.ui.scheduleOutline(tv.string, language: parent.language)

            let ns = tv.string as NSString
            let caret = min(tv.selectedRange().location, ns.length)
            let local = ns.lineRange(for: NSRange(location: caret, length: 0))
            Highlighter.highlight(storage, language: parent.language, theme: parent.theme, font: font,
                                  paragraph: paragraph, in: local)

            pendingHighlight?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.highlightAll() }
            pendingHighlight = work
            let delay = ns.length > 200_000 ? 0.8 : 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)

            pendingFolds?.cancel()
            let foldWork = DispatchWorkItem { [weak self] in
                self?.textView?.rebuildFolds()
                self?.ruler?.needsDisplay = true
            }
            pendingFolds = foldWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: foldWork)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            tv.updateBracketMatch()
            tv.setNeedsDisplay(tv.visibleRect)
            ruler?.needsDisplay = true
            reportCursor()
        }

        func reportCursor() {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            var line = 1
            var lineStart = 0
            var i = 0
            while i < loc {
                if ns.character(at: i) == 10 { line += 1; lineStart = i + 1 }
                i += 1
            }
            let pos = CursorPosition(line: line, column: loc - lineStart + 1)
            let state = parent.ui
            let text = tv.string
            DispatchQueue.main.async {
                if state.cursor != pos { state.cursor = pos }
                state.updateFindMatchStatus(text: text, caret: loc)
            }
        }
    }
}
