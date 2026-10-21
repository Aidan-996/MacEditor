import Foundation

enum Language: String, CaseIterable {
    case swift = "Swift", python = "Python", javascript = "JavaScript", typescript = "TypeScript"
    case json = "JSON", markdown = "Markdown", c = "C", cpp = "C++", go = "Go", rust = "Rust"
    case html = "HTML", css = "CSS", shell = "Shell", plain = "Plain Text"

    static func detect(url: URL?) -> Language {
        guard let ext = url?.pathExtension.lowercased() else { return .plain }
        switch ext {
        case "swift": return .swift
        case "py", "pyw": return .python
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "json": return .json
        case "md", "markdown", "mdown": return .markdown
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx", "mm", "m": return .cpp
        case "go": return .go
        case "rs": return .rust
        case "html", "htm", "xml", "xhtml", "svg", "plist": return .html
        case "css", "scss", "less": return .css
        case "sh", "bash", "zsh", "command": return .shell
        default: return .plain
        }
    }
}

extension Language {
    private static func count(_ pattern: String, in s: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return 0 }
        return re.numberOfMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
    }

    /// Heuristic content sniffing for untitled / extension-less documents.
    static func detect(content: String) -> Language {
        let head = String(content.prefix(6000))
        let t = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .plain }
        let lower = t.lowercased()

        if t.hasPrefix("#!") {
            let first = lower.prefix { $0 != "\n" }
            if first.contains("python") { return .python }
            if first.contains("node") || first.contains("deno") { return .javascript }
            return .shell
        }
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") || lower.hasPrefix("<?xml") { return .html }
        if t.hasPrefix("<"), count(#"</?(html|head|body|div|span|p|a|ul|li|table|script|style|meta|link|svg|section|h[1-6])\b"#, in: lower) >= 2 {
            return .html
        }
        if (t.hasPrefix("{") || t.hasPrefix("[")), content.utf8.count < 5_000_000,
           (try? JSONSerialization.jsonObject(with: Data(content.utf8), options: [.fragmentsAllowed])) != nil {
            return .json
        }

        let scores: [(Language, Int)] = [
            (.swift, count(#"^\s*import (Foundation|SwiftUI|UIKit|AppKit|Combine)\b|\bguard let\b|\bfunc \w+\(.*\)\s*(->|\{)|\b(var|let) \w+: [A-Z]\w*|@(State|Published|main|objc)\b"#, in: head) * 2),
            (.python, count(#"^\s*def \w+\(.*\)\s*(->.*)?:\s*$|^\s*(from \w[\w.]* )?import \w+|\bself\.|^\s*elif\b|^\s*class \w+.*:\s*$|print\("#, in: head)),
            (.javascript, count(#"\bfunction\s*\w*\s*\(|\bconst \w+ =|=>|\bconsole\.\w+|\brequire\(|\bdocument\.|module\.exports"#, in: head)),
            (.typescript, count(#"\binterface \w+ \{|: (string|number|boolean)\b|\bexport type\b"#, in: head) * 2),
            (.go, count(#"^package \w+|\bfunc (\(\w+ \*?\w+\) )?\w+\(|:=|\bfmt\."#, in: head) * 2),
            (.rust, count(#"\bfn \w+\(|\blet mut\b|\bimpl\b|\bpub fn\b|println!|use std::"#, in: head) * 2),
            (.c, count(#"^#include\s*[<"]|\bint main\s*\(|\bprintf\(|\bmalloc\("#, in: head) * 2),
            (.cpp, count(#"\bstd::|\bnamespace \w+|\btemplate\s*<|#include <(iostream|vector|string)>"#, in: head) * 2),
            (.css, count(#"^[.#]?[\w-][\w\s.#:>,-]*\{\s*$|^\s*[\w-]+\s*:\s*[^;{]+;\s*$"#, in: head)),
            (.shell, count(#"^\s*(echo|export|cd|source|alias)\s|^\s*if \[|\$\{?\w+\}?|^\s*fi\s*$"#, in: head)),
            (.markdown, count(#"^#{1,6} \S|^```|^\s*[-*] \[[ xX]\]|\[[^\]]+\]\([^)]+\)|^\s*> \S|^\s*[-*+] \S"#, in: head)),
        ]
        if let best = scores.max(by: { $0.1 < $1.1 }), best.1 >= 2 { return best.0 }
        return .plain
    }
}
