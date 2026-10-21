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

/// NSTextView with auto-indent, current-line highlight, bracket matching and file-drop-to-open.
final class CodeTextView: NSTextView {
    var tabWidth: Int = 4
    var commentStyle: CommentStyle = .none
    var currentLineColor: NSColor = .clear
    var bracketColor: NSColor = .clear
    private var bracketRanges: [NSRange] = []

    override func insertNewline(_ sender: Any?) {
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

    // MARK: Line editing commands (reached via the responder chain)

    private func replace(_ range: NSRange, with text: String, select: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(select)
        scrollRangeToVisible(select)
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

    // MARK: Current line

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let ns = string as NSString
        let loc = min(sel.location, ns.length)
        var lineRect: NSRect
        if ns.length == 0 || (loc == ns.length && ns.character(at: ns.length - 1) == 10) {
            lineRect = lm.extraLineFragmentRect
        } else {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            let glyphs = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            lineRect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        }
        guard lineRect.height > 0 else { return }
        lineRect.origin.x = 0
        lineRect.size.width = bounds.width
        lineRect.origin.y += textContainerOrigin.y
        currentLineColor.setFill()
        lineRect.intersection(rect).fill()
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
            40: (41, true), 91: (93, true), 123: (125, true),   // ( [ {
            41: (40, false), 93: (91, false), 125: (123, false) // ) ] }
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
