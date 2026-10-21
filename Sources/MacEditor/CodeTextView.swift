import AppKit

enum CommentStyle {
    case line(String)
    case block(String, String)
    case none

    static func `for`(_ lang: Language) -> CommentStyle {
        switch lang {
        case .swift, .javascript, .typescript, .c, .cpp, .go, .rust: return .line("//")
        case .python, .shell: return .line("#")
        case .html, .markdown: return .block("<!--", "-->")
        case .css: return .block("/*", "*/")
        case .json, .plain: return .none
        }
    }
}

/// NSTextView with auto-indent, multi-cursor / column select, folding hooks,
/// invisible characters, indent guides, current-line highlight, bracket matching.
final class CodeTextView: NSTextView {
    var tabWidth: Int = 4
    var commentStyle: CommentStyle = .none
    var currentLineColor: NSColor = .clear
    var bracketColor: NSColor = .clear
    var indentGuideColor: NSColor = .clear
    var invisibleColor: NSColor = .clear
    var showInvisibles = false
    var showIndentGuides = true

    /// Extra carets / selections (primary is `selectedRange()`).
    private(set) var extraSelections: [NSRange] = []
    private var columnAnchor: (line: Int, col: Int)?
    private var isColumnDragging = false
    private var bracketRanges: [NSRange] = []

    /// Fold regions currently available / applied.
    var foldRegions: [FoldRegion] = []
    private(set) var foldedHeaders: Set<Int> = [] // startLine values that are folded

    weak var editorUI: EditorUIState?

    // MARK: - Multi-cursor helpers

    func allSelectionRanges() -> [NSRange] {
        var ranges = [selectedRange()]
        ranges.append(contentsOf: extraSelections)
        return ranges.sorted { $0.location > $1.location }
    }

    func clearExtraCursors() {
        extraSelections = []
        needsDisplay = true
    }

    func addCursor(at charIndex: Int) {
        let loc = max(0, min(charIndex, (string as NSString).length))
        let r = NSRange(location: loc, length: 0)
        if selectedRange() == r { return }
        if !extraSelections.contains(where: { $0 == r }) {
            extraSelections.append(r)
            needsDisplay = true
        }
    }

    /// ⌥⌘↓ / mouse: add caret on next / previous line same column.
    @objc func addCursorBelow(_ sender: Any?) { addCursorOnAdjacentLine(delta: 1) }
    @objc func addCursorAbove(_ sender: Any?) { addCursorOnAdjacentLine(delta: -1) }

    private func addCursorOnAdjacentLine(delta: Int) {
        let ns = string as NSString
        let primary = selectedRange()
        let (line, col) = lineColumn(for: primary.location, in: ns)
        let targetLine = line + delta
        guard targetLine >= 1 else { NSSound.beep(); return }
        let loc = location(line: targetLine, column: col, in: ns)
        addCursor(at: loc)
    }

    @objc func selectNextOccurrence(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        guard sel.length > 0 else { NSSound.beep(); return }
        let word = ns.substring(with: sel)
        let searchStart = NSMaxRange(sel)
        var found = ns.range(of: word, options: [], range: NSRange(location: searchStart, length: ns.length - searchStart))
        if found.location == NSNotFound {
            found = ns.range(of: word, options: [], range: NSRange(location: 0, length: max(0, sel.location)))
        }
        guard found.location != NSNotFound, found != sel else { NSSound.beep(); return }
        if !extraSelections.contains(where: { $0 == sel }) {
            extraSelections.append(sel)
        }
        setSelectedRange(found)
        scrollRangeToVisible(found)
        needsDisplay = true
    }

    // MARK: - Input applied to every cursor

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text: String
        if let s = insertString as? String { text = s }
        else if let s = insertString as? NSAttributedString { text = s.string }
        else { super.insertText(insertString, replacementRange: replacementRange); return }

        let ranges = allSelectionRanges()
        if ranges.count <= 1 || hasMarkedText() {
            super.insertText(insertString, replacementRange: replacementRange)
            clearExtraCursors()
            return
        }
        undoManager?.beginUndoGrouping()
        var carets: [NSRange] = []
        for range in ranges {
            guard shouldChangeText(in: range, replacementString: text) else { continue }
            textStorage?.replaceCharacters(in: range, with: text)
            let inserted = (text as NSString).length
            carets.append(NSRange(location: range.location + inserted, length: 0))
        }
        didChangeText()
        undoManager?.endUndoGrouping()
        let all = carets.sorted { $0.location < $1.location }
        if let first = all.first {
            setSelectedRange(first)
            extraSelections = Array(all.dropFirst())
        }
        needsDisplay = true
    }

    override func deleteBackward(_ sender: Any?) {
        let ranges = allSelectionRanges()
        if ranges.count <= 1 {
            super.deleteBackward(sender)
            clearExtraCursors()
            return
        }
        var newCarets: [NSRange] = []
        for range in ranges {
            var r = range
            if r.length == 0 {
                guard r.location > 0 else { newCarets.append(r); continue }
                r = NSRange(location: r.location - 1, length: 1)
            }
            guard shouldChangeText(in: r, replacementString: "") else { continue }
            textStorage?.replaceCharacters(in: r, with: "")
            didChangeText()
            newCarets.append(NSRange(location: r.location, length: 0))
        }
        let sorted = newCarets.sorted { $0.location < $1.location }
        if let first = sorted.first {
            setSelectedRange(first)
            extraSelections = Array(sorted.dropFirst())
        }
        needsDisplay = true
    }

    override func insertNewline(_ sender: Any?) {
        if allSelectionRanges().count > 1 {
            insertText("\n", replacementRange: selectedRange())
            // Re-indent each caret lightly: skip complex auto-indent for multi
            return
        }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let before = ns.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))
        let indent = String(before.prefix { $0 == " " || $0 == "\t" })
        var extra = ""
        if let last = before.trimmingCharacters(in: .whitespaces).last, "{[(:".contains(last) {
            extra = String(repeating: " ", count: tabWidth)
        }
        super.insertNewline(sender)
        let toInsert = indent + extra
        if !toInsert.isEmpty {
            insertText(toInsert, replacementRange: selectedRange())
        }
    }

    override func insertTab(_ sender: Any?) {
        insertText(String(repeating: " ", count: tabWidth), replacementRange: selectedRange())
    }

    // MARK: - Mouse: ⌥-click add cursor, ⌥-drag column select

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let point = convert(event.locationInWindow, from: nil)
            if event.clickCount >= 1 {
                isColumnDragging = true
                let idx = charIndexForInsertion(at: point)
                let ns = string as NSString
                let (line, col) = lineColumn(for: idx, in: ns)
                columnAnchor = (line, col)
                if event.modifierFlags.contains(.command) {
                    // ⌥⌘-click: add cursor without clearing
                    addCursor(at: idx)
                } else {
                    // ⌥-click starts column mode from this point
                    clearExtraCursors()
                    setSelectedRange(NSRange(location: idx, length: 0))
                }
            }
            return
        }
        clearExtraCursors()
        isColumnDragging = false
        columnAnchor = nil
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isColumnDragging, let anchor = columnAnchor {
            let point = convert(event.locationInWindow, from: nil)
            let idx = charIndexForInsertion(at: point)
            let ns = string as NSString
            let (line, col) = lineColumn(for: idx, in: ns)
            applyColumnSelection(fromLine: anchor.line, fromCol: anchor.col, toLine: line, toCol: col, in: ns)
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isColumnDragging = false
        super.mouseUp(with: event)
    }

    private func applyColumnSelection(fromLine: Int, fromCol: Int, toLine: Int, toCol: Int, in ns: NSString) {
        let lo = min(fromLine, toLine)
        let hi = max(fromLine, toLine)
        let c0 = min(fromCol, toCol)
        let c1 = max(fromCol, toCol)
        var ranges: [NSRange] = []
        for line in lo...hi {
            let start = location(line: line, column: c0, in: ns)
            let end = location(line: line, column: c1, in: ns)
            ranges.append(NSRange(location: start, length: max(0, end - start)))
        }
        guard let first = ranges.first else { return }
        setSelectedRange(first)
        extraSelections = Array(ranges.dropFirst())
        needsDisplay = true
    }

    private func charIndexForInsertion(at point: NSPoint) -> Int {
        guard let lm = layoutManager, let tc = textContainer else { return 0 }
        let origin = textContainerOrigin
        var p = point
        p.x -= origin.x
        p.y -= origin.y
        var fraction: CGFloat = 0
        let g = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        var c = lm.characterIndexForGlyph(at: g)
        if fraction > 0.5 { c = min(c + 1, (string as NSString).length) }
        return c
    }

    private func lineColumn(for location: Int, in ns: NSString) -> (Int, Int) {
        let loc = min(location, ns.length)
        var line = 1
        var start = 0
        var i = 0
        while i < loc {
            if ns.character(at: i) == 10 { line += 1; start = i + 1 }
            i += 1
        }
        return (line, loc - start + 1)
    }

    private func location(line: Int, column: Int, in ns: NSString) -> Int {
        var current = 1
        var loc = 0
        while current < line && loc < ns.length {
            loc = NSMaxRange(ns.lineRange(for: NSRange(location: loc, length: 0)))
            current += 1
        }
        let lineRange = ns.lineRange(for: NSRange(location: min(loc, max(ns.length - 1, 0)), length: 0))
        var lineLen = lineRange.length
        if lineLen > 0 && ns.character(at: NSMaxRange(lineRange) - 1) == 10 { lineLen -= 1 }
        let col = max(1, min(column, lineLen + 1))
        return lineRange.location + col - 1
    }

    // MARK: - Folding

    func rebuildFolds() {
        foldRegions = FoldBuilder.regions(in: string, tabWidth: tabWidth)
        // Drop folds that no longer exist
        let valid = Set(foldRegions.map(\.startLine))
        foldedHeaders = foldedHeaders.intersection(valid)
        applyFoldVisibility()
    }

    func toggleFold(atLine line: Int) {
        guard foldRegions.contains(where: { $0.startLine == line }) else { return }
        if foldedHeaders.contains(line) {
            foldedHeaders.remove(line)
        } else {
            foldedHeaders.insert(line)
        }
        applyFoldVisibility()
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    func foldRegion(forLine line: Int) -> FoldRegion? {
        foldRegions.first { $0.startLine == line }
    }

    func applyFoldVisibility() {
        guard let lm = layoutManager else { return }
        let ns = string as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard full.length > 0 else { return }
        let fullGlyphs = lm.glyphRange(forCharacterRange: full, actualCharacterRange: nil)
        lm.setNotShownAttribute(false, forGlyphRange: fullGlyphs)
        for region in foldRegions where foldedHeaders.contains(region.startLine) {
            let gr = lm.glyphRange(forCharacterRange: region.hiddenRange, actualCharacterRange: nil)
            if gr.length > 0 {
                lm.setNotShownAttribute(true, forGlyphRange: gr)
            }
        }
        lm.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
    }

    @objc func foldCurrent(_ sender: Any?) {
        let (line, _) = lineColumn(for: selectedRange().location, in: string as NSString)
        // Prefer innermost fold whose header is at or above caret line and covers caret
        if let region = foldRegions.last(where: { $0.startLine <= line && $0.endLine >= line }) {
            toggleFold(atLine: region.startLine)
        } else {
            NSSound.beep()
        }
    }

    @objc func unfoldAll(_ sender: Any?) {
        foldedHeaders.removeAll()
        applyFoldVisibility()
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    // MARK: Line editing commands

    private func replace(_ range: NSRange, with text: String, select: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(select)
        scrollRangeToVisible(select)
        clearExtraCursors()
    }

    @objc func toggleComment(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        var range = ns.lineRange(for: sel)
        var block = ns.substring(with: range)
        if block.hasSuffix("\n") { block.removeLast(); range.length -= 1 }
        let result: String
        switch commentStyle {
        case .none:
            NSSound.beep(); return
        case .line(let p):
            let lines = block.components(separatedBy: "\n")
            let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(p)
            }
            let minIndent = nonEmpty.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
            result = lines.map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
                if allCommented {
                    guard let r = line.range(of: p) else { return line }
                    let head = String(line[..<r.lowerBound])
                    var tail = String(line[r.upperBound...])
                    if tail.hasPrefix(" ") { tail.removeFirst() }
                    return head + tail
                } else {
                    let idx = line.index(line.startIndex, offsetBy: min(minIndent, line.count))
                    return String(line[..<idx]) + p + " " + String(line[idx...])
                }
            }.joined(separator: "\n")
        case .block(let open, let close):
            let trimmed = block.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(open) && trimmed.hasSuffix(close) && trimmed.count >= open.count + close.count {
                var inner = String(trimmed.dropFirst(open.count).dropLast(close.count))
                if inner.hasPrefix(" ") { inner.removeFirst() }
                if inner.hasSuffix(" ") { inner.removeLast() }
                let indent = String(block.prefix { $0 == " " || $0 == "\t" })
                result = indent + inner
            } else {
                let indent = String(block.prefix { $0 == " " || $0 == "\t" })
                let body = String(block.dropFirst(indent.count))
                result = indent + open + " " + body + " " + close
            }
        }
        let newLength = (result as NSString).length
        let newSel: NSRange
        if sel.length == 0 {
            let moved = sel.location + (newLength - range.length)
            newSel = NSRange(location: max(range.location, min(moved, range.location + newLength)), length: 0)
        } else {
            newSel = NSRange(location: range.location, length: newLength)
        }
        replace(range, with: result, select: newSel)
    }

    @objc func duplicateLine(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        let range = ns.lineRange(for: sel)
        var text = ns.substring(with: range)
        var insertAt = NSMaxRange(range)
        if !text.hasSuffix("\n") { text = "\n" + text; insertAt = NSMaxRange(range) }
        let shift = (text as NSString).length
        replace(NSRange(location: insertAt, length: 0), with: text,
                select: NSRange(location: sel.location + shift, length: sel.length))
    }

    @objc func moveLineUp(_ sender: Any?) { moveLines(up: true) }
    @objc func moveLineDown(_ sender: Any?) { moveLines(up: false) }

    private func moveLines(up: Bool) {
        let ns = string as NSString
        let sel = selectedRange()
        let cur = ns.lineRange(for: sel)
        if up {
            guard cur.location > 0 else { NSSound.beep(); return }
            let prev = ns.lineRange(for: NSRange(location: cur.location - 1, length: 0))
            var a = ns.substring(with: cur), b = ns.substring(with: prev)
            if !a.hasSuffix("\n") { a += "\n"; if b.hasSuffix("\n") { b.removeLast() } }
            replace(NSRange(location: prev.location, length: prev.length + cur.length), with: a + b,
                    select: NSRange(location: sel.location - prev.length, length: sel.length))
        } else {
            guard NSMaxRange(cur) < ns.length else { NSSound.beep(); return }
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(cur), length: 0))
            var a = ns.substring(with: cur), b = ns.substring(with: next)
            if !b.hasSuffix("\n") { b += "\n"; if a.hasSuffix("\n") { a.removeLast() } }
            replace(NSRange(location: cur.location, length: cur.length + next.length), with: b + a,
                    select: NSRange(location: sel.location + (b as NSString).length, length: sel.length))
        }
    }

    // MARK: Drawing — current line, indent guides, invisibles, extra carets

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        let sel = selectedRange()
        if sel.length == 0 && extraSelections.isEmpty {
            let ns = string as NSString
            let loc = min(sel.location, ns.length)
            var lineRect: NSRect
            if ns.length == 0 || (loc == ns.length && ns.length > 0 && ns.character(at: ns.length - 1) == 10) {
                lineRect = lm.extraLineFragmentRect
            } else if ns.length == 0 {
                lineRect = .zero
            } else {
                let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
                let glyphs = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
                lineRect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            }
            if lineRect.height > 0 {
                lineRect.origin.x = 0
                lineRect.size.width = bounds.width
                lineRect.origin.y += textContainerOrigin.y
                currentLineColor.setFill()
                lineRect.intersection(rect).fill()
            }
        }
        if showIndentGuides { drawIndentGuides(in: rect, layoutManager: lm, textContainer: tc) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if showInvisibles { drawInvisibles(in: dirtyRect) }
        drawExtraCarets(in: dirtyRect)
        drawExtraSelections(in: dirtyRect)
    }

    private func drawIndentGuides(in rect: NSRect, layoutManager lm: NSLayoutManager, textContainer tc: NSTextContainer) {
        guard let font = self.font else { return }
        let charWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        guard charWidth > 0 else { return }
        let ns = string as NSString
        let visible = visibleRect
        lm.ensureLayout(forBoundingRect: visible, in: tc)
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        indentGuideColor.setStroke()
        var index = charRange.location
        let end = NSMaxRange(charRange)
        while index < end {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            let depth = FoldBuilder.indent(of: line, tabWidth: tabWidth)
            if depth >= tabWidth {
                let glyphIndex = lm.glyphIndexForCharacter(at: index)
                let fragment = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
                var yRect = fragment
                yRect.origin.y += textContainerOrigin.y
                var col = tabWidth
                while col <= depth {
                    let x = textContainerOrigin.x + tc.lineFragmentPadding + CGFloat(col) * charWidth
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: x, y: yRect.minY))
                    path.line(to: NSPoint(x: x, y: yRect.maxY))
                    path.lineWidth = 1
                    path.stroke()
                    col += tabWidth
                }
            }
            index = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
    }

    private func drawInvisibles(in rect: NSRect) {
        guard let lm = layoutManager, let tc = textContainer, let font = self.font else { return }
        let ns = string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: invisibleColor,
        ]
        let visible = visibleRect.intersection(rect)
        lm.ensureLayout(forBoundingRect: visible, in: tc)
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        for i in charRange.location..<NSMaxRange(charRange) {
            let ch = ns.character(at: i)
            let symbol: String?
            switch ch {
            case 32: symbol = "·"
            case 9: symbol = "→"
            case 10: symbol = "¬"
            default: symbol = nil
            }
            guard let symbol else { continue }
            let g = lm.glyphIndexForCharacter(at: i)
            let origin = lm.location(forGlyphAt: g)
            let fragment = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil, withoutAdditionalLayout: true)
            let p = NSPoint(x: textContainerOrigin.x + origin.x,
                            y: textContainerOrigin.y + fragment.minY + origin.y - font.ascender)
            (symbol as NSString).draw(at: p, withAttributes: attrs)
        }
    }

    private func drawExtraCarets(in rect: NSRect) {
        guard let lm = layoutManager, let tc = textContainer else { return }
        insertionPointColor.setFill()
        for range in extraSelections where range.length == 0 {
            let loc = min(range.location, (string as NSString).length)
            let g = lm.glyphIndexForCharacter(at: max(0, loc))
            let origin = lm.location(forGlyphAt: g)
            let fragment = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil, withoutAdditionalLayout: true)
            let height = fragment.height > 0 ? fragment.height : (font?.boundingRectForFont.height ?? 14)
            let caret = NSRect(
                x: textContainerOrigin.x + origin.x,
                y: textContainerOrigin.y + fragment.minY,
                width: 2,
                height: height
            )
            caret.intersection(rect).fill()
            _ = tc
        }
    }

    private func drawExtraSelections(in rect: NSRect) {
        guard let lm = layoutManager, let tc = textContainer else { return }
        let color = (selectedTextAttributes[.backgroundColor] as? NSColor) ?? NSColor.selectedTextBackgroundColor
        color.withAlphaComponent(0.45).setFill()
        for range in extraSelections where range.length > 0 {
            let gr = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let bounds = lm.boundingRect(forGlyphRange: gr, in: tc)
            var fill = bounds
            fill.origin.y += textContainerOrigin.y
            fill.origin.x += textContainerOrigin.x
            fill.intersection(rect).fill()
        }
    }

    // MARK: Bracket matching

    func updateBracketMatch() {
        guard let lm = layoutManager else { return }
        for r in bracketRanges { lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r) }
        bracketRanges = []
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let ns = string as NSString
        let pairs: [unichar: (unichar, Bool)] = [
            40: (41, true), 91: (93, true), 123: (125, true),
            41: (40, false), 93: (91, false), 125: (123, false),
        ]
        var candidates: [Int] = []
        if sel.location > 0 { candidates.append(sel.location - 1) }
        if sel.location < ns.length { candidates.append(sel.location) }
        for pos in candidates {
            let ch = ns.character(at: pos)
            guard let pair = pairs[ch] else { continue }
            let other = pair.0
            let forward = pair.1
            var depth = 0
            var i = pos
            var steps = 0
            while i >= 0 && i < ns.length && steps < 50_000 {
                let c = ns.character(at: i)
                if c == ch { depth += 1 } else if c == other { depth -= 1 }
                if depth == 0 {
                    bracketRanges = [NSRange(location: pos, length: 1), NSRange(location: i, length: 1)]
                    for r in bracketRanges {
                        lm.addTemporaryAttribute(.backgroundColor, value: bracketColor, forCharacterRange: r)
                    }
                    return
                }
                i += forward ? 1 : -1
                steps += 1
            }
        }
    }

    // MARK: Drag & drop files to open

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            for url in urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
            return true
        }
        return super.performDragOperation(sender)
    }
}
