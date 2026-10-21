import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var theme: Theme = .oneDark { didSet { needsDisplay = true } }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 48
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(refresh), name: NSTextView.didChangeSelectionNotification, object: textView)
        textView.postsFrameChangedNotifications = true
        nc.addObserver(self, selector: #selector(refresh), name: NSView.frameDidChangeNotification, object: textView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        nc.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func refresh() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.ns(theme.background).setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let ns = tv.string as NSString
        let editorSize = tv.font?.pointSize ?? 13
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: max(editorSize - 1.5, 9), weight: .regular)
        let dim: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.ns(\.gutterText)]
        let bright: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.ns(\.gutterActiveText)]

        let visible = tv.visibleRect
        lm.ensureLayout(forBoundingRect: visible, in: tc)
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Line numbers before the visible range, and the caret's line.
        let start = charRange.location
        let caret = min(tv.selectedRange().location, ns.length)
        var lineNumber = 1
        var caretLine = 1
        var i = 0
        let limit = max(start, caret)
        while i < limit {
            if ns.character(at: i) == 10 {
                if i < start { lineNumber += 1 }
                if i < caret { caretLine += 1 }
            }
            i += 1
        }

        let containerOrigin = tv.textContainerOrigin
        var fallbackBaseline: CGFloat = labelFont.ascender

        // Draws number so that its baseline matches the baseline of the first visual row of the line.
        func draw(_ number: Int, fragment: NSRect, baselineInFragment: CGFloat) {
            let attrs = number == caretLine ? bright : dim
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attrs)
            let baselineInTV = NSPoint(x: 0, y: containerOrigin.y + fragment.minY + baselineInFragment)
            let p = convert(baselineInTV, from: tv)
            let x = ruleThickness - size.width - 12
            let y = isFlipped ? p.y - labelFont.ascender : p.y + labelFont.descender
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }

        var index = start
        while index < NSMaxRange(charRange) {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let glyphIndex = lm.glyphIndexForCharacter(at: index)
            let fragment = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
            let baseline = lm.location(forGlyphAt: glyphIndex).y
            fallbackBaseline = baseline
            draw(lineNumber, fragment: fragment, baselineInFragment: baseline)
            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
        if NSMaxRange(charRange) >= ns.length, lm.extraLineFragmentTextContainer != nil {
            draw(lineNumber, fragment: lm.extraLineFragmentRect, baselineInFragment: fallbackBaseline)
        }

        // Grow the gutter for big files (never during the same draw pass).
        let digits = max(3, String(max(lineNumber, caretLine)).count)
        let needed = ceil(CGFloat(digits) * labelFont.pointSize * 0.62 + 28)
        if needed > ruleThickness + 0.5 {
            DispatchQueue.main.async { [weak self] in self?.ruleThickness = needed }
        }
    }
}
