import AppKit
import Foundation

// MARK: - Indent-based fold regions

struct FoldRegion: Equatable {
    /// 1-based line of the fold header (stays visible).
    let startLine: Int
    /// 1-based last line included in the fold (hidden).
    let endLine: Int
    /// Character range to hide (from start of line after header through end of endLine).
    let hiddenRange: NSRange
}

enum FoldBuilder {
    /// Indent depth in spaces (tabs count as `tabWidth`).
    static func indent(of line: String, tabWidth: Int) -> Int {
        var n = 0
        for ch in line {
            if ch == " " { n += 1 }
            else if ch == "\t" { n += tabWidth }
            else { break }
        }
        return n
    }

    static func lineInfos(_ text: String, tabWidth: Int) -> [(start: Int, length: Int, indent: Int, blank: Bool)] {
        let ns = text as NSString
        if ns.length == 0 { return [(0, 0, 0, true)] }
        var infos: [(start: Int, length: Int, indent: Int, blank: Bool)] = []
        var loc = 0
        while loc < ns.length {
            let range = ns.lineRange(for: NSRange(location: loc, length: 0))
            var line = ns.substring(with: range)
            if line.hasSuffix("\n") { line.removeLast() }
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            infos.append((range.location, range.length, blank ? -1 : indent(of: line, tabWidth: tabWidth), blank))
            let next = NSMaxRange(range)
            if next <= loc { break }
            loc = next
        }
        return infos
    }

    static func regions(in text: String, tabWidth: Int) -> [FoldRegion] {
        let lines = lineInfos(text, tabWidth: tabWidth)
        guard lines.count >= 2 else { return [] }
        var result: [FoldRegion] = []
        for i in 0..<(lines.count - 1) {
            let cur = lines[i]
            if cur.blank || cur.indent < 0 { continue }
            // Look ahead for deeper indent
            var j = i + 1
            while j < lines.count && lines[j].blank { j += 1 }
            guard j < lines.count, lines[j].indent > cur.indent else { continue }
            let childIndent = lines[j].indent
            var end = j
            var k = j + 1
            while k < lines.count {
                if lines[k].blank {
                    end = k
                    k += 1
                    continue
                }
                if lines[k].indent >= childIndent {
                    end = k
                    k += 1
                } else {
                    break
                }
            }
            // Trim trailing blank lines from fold
            while end > j && lines[end].blank { end -= 1 }
            guard end >= j else { continue }
            let hideStart = lines[i + 1].start
            let hideEnd = lines[end].start + lines[end].length
            let hidden = NSRange(location: hideStart, length: max(0, hideEnd - hideStart))
            guard hidden.length > 0 else { continue }
            result.append(FoldRegion(startLine: i + 1, endLine: end + 1, hiddenRange: hidden))
        }
        return result
    }
}

// MARK: - Document outline

struct OutlineItem: Identifiable, Equatable {
    var id: String { "\(line)|\(depth)|\(title)" }
    let line: Int
    let title: String
    let depth: Int
}

enum OutlineBuilder {
    static func build(text: String, language: Language) -> [OutlineItem] {
        switch language {
        case .markdown:
            return markdown(text)
        default:
            return code(text, language: language)
        }
    }

    private static func markdown(_ text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            var depth = 0
            for ch in trimmed {
                if ch == "#" { depth += 1 } else { break }
            }
            guard depth >= 1 && depth <= 6 else { continue }
            let title = trimmed.dropFirst(depth).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            items.append(OutlineItem(line: i + 1, title: String(title), depth: depth - 1))
        }
        return items
    }

    private static func code(_ text: String, language: Language) -> [OutlineItem] {
        let patterns: [String]
        switch language {
        case .swift:
            patterns = [
                #"^\s*(?:public |private |internal |open |fileprivate )*(?:final )?(?:class|struct|enum|actor|extension|func|protocol)\s+(\w+)"#,
            ]
        case .python:
            patterns = [#"^\s*(?:async\s+)?(?:def|class)\s+(\w+)"#]
        case .javascript, .typescript:
            patterns = [
                #"^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)"#,
                #"^\s*(?:export\s+)?(?:class)\s+(\w+)"#,
                #"^\s*(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\("#,
            ]
        case .go:
            patterns = [#"^\s*func\s+(?:\([^)]+\)\s+)?(\w+)"#, #"^\s*type\s+(\w+)"#]
        case .rust:
            patterns = [#"^\s*(?:pub\s+)?(?:async\s+)?(?:fn|struct|enum|trait|impl)\s+(\w+)"#]
        case .c, .cpp:
            patterns = [#"^\s*(?:[\w:\*&<>\s]+)\s+(\w+)\s*\([^;]*\)\s*\{?\s*$"#]
        default:
            patterns = [
                #"^\s*(?:def|class|function|func|fn|struct|enum|extension)\s+(\w+)"#,
            ]
        }
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }
        var items: [OutlineItem] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for re in regexes {
            for m in re.matches(in: text, options: [], range: full) {
                guard m.numberOfRanges >= 2 else { continue }
                let nameRange = m.range(at: 1)
                guard nameRange.location != NSNotFound else { continue }
                let name = ns.substring(with: nameRange)
                let line = lineNumber(of: m.range.location, in: ns)
                let depth = FoldBuilder.indent(of: ns.substring(with: ns.lineRange(for: m.range)), tabWidth: 4) / 4
                items.append(OutlineItem(line: line, title: name, depth: min(depth, 4)))
            }
        }
        items.sort { $0.line < $1.line }
        // Dedupe same line
        var seen = Set<Int>()
        return items.filter { seen.insert($0.line).inserted }
    }

    private static func lineNumber(of location: Int, in ns: NSString) -> Int {
        var line = 1
        var i = 0
        let lim = min(location, ns.length)
        while i < lim {
            if ns.character(at: i) == 10 { line += 1 }
            i += 1
        }
        return line
    }
}

// MARK: - Find match counter (uses system Find pasteboard)

enum FindMatchCounter {
    static func findPasteboardString() -> String? {
        let pb = NSPasteboard(name: .find)
        return pb.string(forType: .string).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Returns (current 1-based index, total) for the caret relative to matches of `query`.
    static func status(in text: String, query: String, caret: Int, regex: Bool = false) -> (Int, Int)? {
        let ranges = matches(in: text, query: query, regex: regex)
        guard !ranges.isEmpty else { return nil }
        var index = 0
        for (i, r) in ranges.enumerated() {
            if NSLocationInRange(caret, r) || caret <= r.location {
                index = i
                break
            }
            index = i
            if caret >= NSMaxRange(r) { index = i }
        }
        // Prefer match containing caret
        if let i = ranges.firstIndex(where: { NSLocationInRange(caret, $0) || caret == $0.location }) {
            index = i
        } else if let i = ranges.lastIndex(where: { NSMaxRange($0) <= caret }) {
            index = i
        } else {
            index = 0
        }
        return (index + 1, ranges.count)
    }

    static func matches(in text: String, query: String, regex: Bool) -> [NSRange] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard !query.isEmpty else { return [] }
        if regex {
            guard let re = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) else { return [] }
            return re.matches(in: text, options: [], range: full).map(\.range)
        }
        var ranges: [NSRange] = []
        var search = full
        while search.length > 0 {
            let found = ns.range(of: query, options: [.caseInsensitive], range: search)
            if found.location == NSNotFound { break }
            ranges.append(found)
            let next = NSMaxRange(found)
            search = NSRange(location: next, length: ns.length - next)
        }
        return ranges
    }
}

// MARK: - External file change watcher

final class DocumentFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private(set) var path: String?
    /// Bumped when we write/save so we can ignore our own saves briefly.
    private var ignoreUntil: Date = .distantPast

    var onChanged: (() -> Void)?

    func watch(url: URL?) {
        stop()
        guard let url, url.isFileURL else { return }
        path = url.path
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            if Date() < self.ignoreUntil { return }
            self.onChanged?()
        }
        src.setCancelHandler { [weak self] in
            if let self = self, self.fd >= 0 {
                close(self.fd)
                self.fd = -1
            }
        }
        source = src
        src.resume()
    }

    func noteLocalSave() {
        ignoreUntil = Date().addingTimeInterval(1.2)
    }

    func stop() {
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd); fd = -1 }
        path = nil
    }

    deinit { stop() }
}
