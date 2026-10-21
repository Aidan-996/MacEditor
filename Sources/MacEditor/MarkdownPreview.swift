import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    var markdown: String
    var theme: Theme

    final class Coordinator { var lastHTML = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let html = MarkdownRenderer.html(markdown, theme: theme)
        guard html != context.coordinator.lastHTML else { return }
        context.coordinator.lastHTML = html
        web.loadHTMLString(html, baseURL: nil)
    }
}

enum MarkdownRenderer {
    static let css = """
    :root { color-scheme: light dark; }
    body { font: 14px -apple-system, sans-serif; line-height: 1.6; padding: 16px 24px; color: #1d1d1f; background: transparent; }
    @media (prefers-color-scheme: dark) { body { color: #e6e6e6; } a { color: #6bb5ff; } code, pre { background: #2a2a2e !important; } blockquote { color: #aaa; } }
    code { font-family: ui-monospace, Menlo, monospace; background: #f2f2f5; padding: 1px 4px; border-radius: 4px; }
    pre { background: #f2f2f5; padding: 10px; border-radius: 6px; overflow-x: auto; }
    pre code { padding: 0; background: none; }
    blockquote { border-left: 4px solid #8884; margin: 0; padding-left: 12px; color: #666; }
    img { max-width: 100%; }
    h1, h2 { border-bottom: 1px solid #8883; padding-bottom: 4px; }
    """

    static func themeCSS(_ t: Theme) -> String {
        let bg = Theme.css(t.background), fg = Theme.css(t.text), code = Theme.css(t.chrome)
        let link = Theme.css(t.function), muted = Theme.css(t.comment), head = Theme.css(t.heading)
        return """
        body { background: \(bg) !important; color: \(fg) !important; }
        a { color: \(link) !important; }
        h1, h2, h3, h4, h5, h6 { color: \(head); }
        code, pre { background: \(code) !important; }
        blockquote { color: \(muted) !important; }
        """
    }

    static func html(_ md: String, theme: Theme) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"><style>\(css)\n\(themeCSS(theme))</style></head><body>\(body(md))</body></html>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let inlinePatterns: [(String, String)] = [
        (#"`([^`]+)`"#, "<code>$1</code>"),
        (#"!\[([^\]]*)\]\(([^)\s]+)\)"#, "<img alt=\"$1\" src=\"$2\">"),
        (#"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>"),
        (#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"),
        (#"__(.+?)__"#, "<strong>$1</strong>"),
        (#"\*(.+?)\*"#, "<em>$1</em>"),
        (#"~~(.+?)~~"#, "<del>$1</del>"),
    ]
    private static let inlineRules: [(NSRegularExpression, String)] = inlinePatterns.map { pair in
        (try! NSRegularExpression(pattern: pair.0), pair.1)
    }

    static func inline(_ s: String) -> String {
        var out = escape(s)
        for (re, tpl) in inlineRules {
            out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: tpl)
        }
        return out
    }

    static func body(_ md: String) -> String {
        var out = ""
        var para: [String] = []
        var listTag: String? = nil
        var inCode = false

        func flushPara() {
            if !para.isEmpty {
                out += "<p>" + inline(para.joined(separator: " ")) + "</p>\n"
                para.removeAll()
            }
        }
        func closeList() {
            if let t = listTag { out += "</\(t)>\n"; listTag = nil }
        }
        func openList(_ tag: String) {
            if listTag != tag { closeList(); out += "<\(tag)>\n"; listTag = tag }
        }

        for line in md.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if inCode { out += "</code></pre>\n"; inCode = false }
                else { flushPara(); closeList(); out += "<pre><code>"; inCode = true }
                continue
            }
            if inCode { out += escape(line) + "\n"; continue }
            if t.isEmpty { flushPara(); closeList(); continue }

            let hashes = t.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), t.dropFirst(hashes).first == " " {
                flushPara(); closeList()
                out += "<h\(hashes)>" + inline(String(t.dropFirst(hashes + 1))) + "</h\(hashes)>\n"
                continue
            }
            if t == "---" || t == "***" || t == "___" { flushPara(); closeList(); out += "<hr>\n"; continue }
            if t.hasPrefix(">") {
                flushPara(); closeList()
                out += "<blockquote>" + inline(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)) + "</blockquote>\n"
                continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                flushPara(); openList("ul")
                var item = String(t.dropFirst(2))
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                else if item.hasPrefix("[x] ") || item.hasPrefix("[X] ") { item = "☑ " + item.dropFirst(4) }
                out += "<li>" + inline(item) + "</li>\n"
                continue
            }
            if let r = t.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
                flushPara(); openList("ol")
                out += "<li>" + inline(String(t[r.upperBound...])) + "</li>\n"
                continue
            }
            closeList()
            para.append(t)
        }
        if inCode { out += "</code></pre>\n" }
        flushPara()
        closeList()
        return out
    }
}
