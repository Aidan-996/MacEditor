import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var textView: CodeTextView?
    var theme: Theme = .oneDark { didSet { needsDisplay = true } }

    private var foldHitZones: [(line: Int, rect: NSRect)] = []

    init(textView: CodeTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 56
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

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for zone in foldHitZones where zone.rect.contains(p) {
            textView?.toggleFold(atLine: zone.line)
            return
        }
        super.mouseDown(with: event)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        foldHitZones = []
        let ns = tv.string as NSString
        let editorSize = tv.font?.pointSize ?? 13
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: max(editorSize - 1.5, 9), weight: .regular)
        let dim: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.ns(\.gutterText)]
        let bright: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.ns(\.gutterActiveText)]
        let foldAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(editorSize - 2, 9), weight: .medium),
            .foregroundColor: theme.ns(\.gutterActiveText),
        ]

        let visible = tv.visibleRect
        lm.ensureLayout(forBoundingRect: visible, in: tc)
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

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
        let foldable = Dictionary(uniqueKeysWithValues: tv.foldRegions.map { ($0.startLine, $0) })

        func draw(_ number: Int, fragment: NSRect, baselineInFragment: CGFloat) {
            // Skip drawing numbers for lines hidden inside a fold
            if isLineHidden(number, tv: tv) { return }

            let attrs = number == caretLine ? bright : dim
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attrs)
            let baselineInTV = NSPoint(x: 0, y: containerOrigin.y + fragment.minY + baselineInFragment)
            let p = convert(baselineInTV, from: tv)
            let x = ruleThickness - size.width - 14
            let y = isFlipped ? p.y - labelFont.ascender : p.y + labelFont.descender
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            if let _ = foldable[number] {
                let folded = tv.foldedHeaders.contains(number)
                let mark = folded ? "▸" : "▾"
                let mSize = (mark as NSString).size(withAttributes: foldAttrs)
                let mx: CGFloat = 4
                let my = y + (size.height - mSize.height) / 2
                (mark as NSString).draw(at: NSPoint(x: mx, y: my), withAttributes: foldAttrs)
                let hit = NSRect(x: 0, y: my - 2, width: 18, height: mSize.height + 4)
                foldHitZones.append((number, hit))
            }
        }

        var index = start
        while index < NSMaxRange(charRange) {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            // Skip glyph layout for fully hidden fold interiors
            if !isCharHidden(index, tv: tv) {
                let glyphIndex = lm.glyphIndexForCharacter(at: index)
                let fragment = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
                let baseline = lm.location(forGlyphAt: glyphIndex).y
                fallbackBaseline = baseline
                if fragment.height > 0.5 || !tv.foldedHeaders.isEmpty {
                    draw(lineNumber, fragment: fragment, baselineInFragment: baseline)
                }
            }
            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
        if NSMaxRange(charRange) >= ns.length, lm.extraLineFragmentTextContainer != nil {
            draw(lineNumber, fragment: lm.extraLineFragmentRect, baselineInFragment: fallbackBaseline)
        }

        let digits = max(3, String(max(lineNumber, caretLine)).count)
        let needed = ceil(CGFloat(digits) * labelFont.pointSize * 0.62 + 36)
        if needed > ruleThickness + 0.5 {
            DispatchQueue.main.async { [weak self] in self?.ruleThickness = needed }
        }
    }

    private func isLineHidden(_ line: Int, tv: CodeTextView) -> Bool {
        for region in tv.foldRegions where tv.foldedHeaders.contains(region.startLine) {
            if line > region.startLine && line <= region.endLine { return true }
        }
        return false
    }

    private func isCharHidden(_ location: Int, tv: CodeTextView) -> Bool {
        for region in tv.foldRegions where tv.foldedHeaders.contains(region.startLine) {
            if NSLocationInRange(location, region.hiddenRange) { return true }
        }
        return false
    }
}
