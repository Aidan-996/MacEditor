import AppKit

struct HighlightRule {
    let regex: NSRegularExpression
    let kind: TokenKind
    let group: Int
    init(_ pattern: String, _ kind: TokenKind, group: Int = 0,
         options: NSRegularExpression.Options = [.anchorsMatchLines]) {
        // Patterns are static; force-try is acceptable here.
        self.regex = try! NSRegularExpression(pattern: pattern, options: options)
        self.kind = kind
        self.group = group
    }
}

enum Highlighter {
    private static func kw(_ words: String) -> String {
        "\\b(?:" + words.split(separator: " ").joined(separator: "|") + ")\\b"
    }
    private static let dq = #"\"(?:\\.|[^\"\\\n])*\""#
    private static let sq = #"'(?:\\.|[^'\\\n])*'"#
    private static let num = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#
    private static let cap = #"\b[A-Z][A-Za-z0-9_]*\b"#
    private static let call = #"\b([A-Za-z_]\w*)(?=\s*\()"#
    private static let lineC = #"//.*$"#
    private static let blockC = #"/\*[\s\S]*?\*/"#
    private static let hashC = #"#.*$"#

    private static func cLike(keywords: String, types: String, extra: [HighlightRule] = [],
                              strings: [String]) -> [HighlightRule] {
        var r: [HighlightRule] = [
            HighlightRule(call, .function, group: 1),
            HighlightRule(cap, .type),
            HighlightRule(kw(types), .type),
            HighlightRule(kw(keywords), .keyword),
            HighlightRule(num, .number),
        ]
        r += extra
        r += strings.map { HighlightRule($0, .string) }
        r += [HighlightRule(lineC, .comment), HighlightRule(blockC, .comment)]
        return r
    }

    private static let jsKeywords = "var let const function return if else for while do switch case default break continue new delete typeof instanceof in of class extends super this import export from as async await yield try catch finally throw null undefined true false"
    private static let jsStrings = [dq, sq, #"`(?:\\.|[^`\\])*`"#]

    private static let cssRules: [HighlightRule] = [
        HighlightRule(#"^[ \t]*([^{}\n;]+?)(?=\s*\{)"#, .tag, group: 1),
        HighlightRule(#"([\w-]+)\s*:(?!:)"#, .attribute, group: 1),
        HighlightRule(#"#[0-9a-fA-F]{3,8}\b|-?\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg|fr)?"#, .number),
        HighlightRule(#"@[\w-]+"#, .keyword),
        HighlightRule(kw("important inherit initial auto none"), .keyword),
        HighlightRule(dq, .string), HighlightRule(sq, .string),
        HighlightRule(blockC, .comment),
    ]

    private static let htmlRules: [HighlightRule] = [
        HighlightRule(#"</?|/?>"#, .punctuation),
        HighlightRule(#"</?([A-Za-z][\w:.-]*)"#, .tag, group: 1),
        HighlightRule(#"<[^<>]*?\s([\w:@.\-]+)(?=\s*=)"#, .attribute, group: 1),
        HighlightRule(#"(?<=\s)([\w:@.\-]+)(?=\s*=\s*["'])"#, .attribute, group: 1),
        HighlightRule(#"=\s*("[^"]*"|'[^']*')"#, .string, group: 1),
        HighlightRule(#"&#?\w+;"#, .number),
        HighlightRule(#"<!DOCTYPE[^>]*>|<\?xml[^>]*\?>"#, .keyword, options: [.caseInsensitive]),
        HighlightRule(#"<!--[\s\S]*?-->"#, .comment),
    ]

    private static let styleBlock = try! NSRegularExpression(
        pattern: #"<style\b[^>]*>([\s\S]*?)</style\s*>"#, options: [.caseInsensitive])
    private static let scriptBlock = try! NSRegularExpression(
        pattern: #"<script\b[^>]*>([\s\S]*?)</script\s*>"#, options: [.caseInsensitive])

    static let rules: [Language: [HighlightRule]] = [
        .swift: cLike(
            keywords: "func var let if else guard return struct class enum protocol extension import for in while repeat switch case default break continue defer do try catch throw throws rethrows async await actor init deinit self Self super nil true false static private public internal fileprivate open final override mutating nonmutating inout some any where as is typealias associatedtype subscript lazy weak unowned convenience required get set willSet didSet",
            types: "Int Double Float String Bool Character Array Dictionary Set Optional Void",
            extra: [HighlightRule(#"@\w+"#, .attribute)],
            strings: ["\"\"\"[\\s\\S]*?\"\"\"", dq]),
        .python: [
            HighlightRule(call, .function, group: 1),
            HighlightRule(cap, .type),
            HighlightRule(kw("int float str bool list dict set tuple bytes object"), .type),
            HighlightRule(kw("def class if elif else return import from as for in while try except finally raise with lambda yield pass break continue and or not is None True False global nonlocal async await assert del self"), .keyword),
            HighlightRule(num, .number),
            HighlightRule(#"^\s*@[\w.]+"#, .attribute),
            HighlightRule(dq, .string), HighlightRule(sq, .string),
            HighlightRule(hashC, .comment),
            HighlightRule(#"("""|''')[\s\S]*?\1"#, .string),
        ],
        .javascript: cLike(keywords: jsKeywords, types: "Object Array String Number Boolean Promise Map Set",
                           strings: jsStrings),
        .typescript: cLike(
            keywords: jsKeywords + " implements interface type enum namespace public private protected readonly abstract declare keyof",
            types: "string number boolean any unknown never void object Object Array Promise Record",
            strings: jsStrings),
        .json: [
            HighlightRule(num, .number),
            HighlightRule(kw("true false null"), .keyword),
            HighlightRule(dq, .string),
            HighlightRule(#"\"(?:\\.|[^\"\\\n])*\"(?=\s*:)"#, .tag),
        ],
        .c: cLike(
            keywords: "auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while NULL true false",
            types: "int char float double long short signed unsigned void bool size_t uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t",
            extra: [HighlightRule(#"^\s*#\s*\w+"#, .keyword), HighlightRule(#"(?<=#include)\s*<[^>\n]+>"#, .string)],
            strings: [dq, sq]),
        .cpp: cLike(
            keywords: "auto break case const constexpr continue default do else enum extern for goto if inline return sizeof static struct switch typedef union volatile while class namespace using template typename public private protected virtual override final new delete this try catch throw nullptr true false operator friend explicit mutable noexcept static_cast dynamic_cast reinterpret_cast const_cast",
            types: "int char float double long short signed unsigned void bool size_t string vector map std",
            extra: [HighlightRule(#"^\s*#\s*\w+"#, .keyword), HighlightRule(#"@\w+"#, .keyword),
                    HighlightRule(#"(?<=#include)\s*<[^>\n]+>"#, .string)],
            strings: [dq, sq]),
        .go: cLike(
            keywords: "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var nil true false iota",
            types: "int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 string bool byte rune error any",
            strings: [dq, sq, #"`[^`]*`"#]),
        .rust: cLike(
            keywords: "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while",
            types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box",
            extra: [HighlightRule(#"#!?\[[^\]]*\]"#, .attribute), HighlightRule(#"\b\w+!"#, .function)],
            strings: [dq]),
        .html: htmlRules,
        .css: cssRules,
        .shell: [
            HighlightRule(kw("if then else elif fi for while until do done case esac in function return local export readonly source exit break continue"), .keyword),
            HighlightRule(kw("echo cd set unset shift printf read test eval exec trap"), .function),
            HighlightRule(#"\$\{?[\w@#?*!$-]+\}?"#, .type),
            HighlightRule(#"(?<=\s)--?[\w-]+"#, .attribute),
            HighlightRule(num, .number),
            HighlightRule(dq, .string), HighlightRule(#"'[^'\n]*'"#, .string),
            HighlightRule(#"(?:^|\s)(#.*)$"#, .comment, group: 1),
        ],
        .markdown: [
            HighlightRule(#"^#{1,6}\s.*$"#, .heading),
            HighlightRule(#"^\s*(?:[-*+]|\d+\.)\s"#, .keyword),
            HighlightRule(#"^>.*$"#, .comment),
            HighlightRule(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, .type),
            HighlightRule(#"(?<![*\w])\*[^*\n]+\*(?!\*)"#, .attribute),
            HighlightRule(#"!?\[[^\]\n]*\]\([^)\n]*\)"#, .function),
            HighlightRule(#"`[^`\n]+`"#, .string),
            HighlightRule(#"^```[\s\S]*?^```"#, .string),
        ],
    ]

    /// Highlights `range` (nil = whole document). Later rules override earlier ones.
    static func highlight(_ storage: NSTextStorage, language: Language, theme: Theme, font: NSFont,
                          paragraph: NSParagraphStyle, in range: NSRange? = nil) {
        let full = NSRange(location: 0, length: storage.length)
        let target = range.map { NSIntersectionRange($0, full) } ?? full
        let textColor = theme.ns(\.text)
        storage.beginEditing()
        storage.addAttributes([.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph], range: target)
        if storage.length <= 2_000_000, target.length > 0 {
            let string = storage.string
            if let langRules = rules[language] {
                apply(langRules, to: storage, string: string, range: target, theme: theme)
            }
            if language == .html {
                for (block, lang) in [(styleBlock, Language.css), (scriptBlock, Language.javascript)] {
                    block.enumerateMatches(in: string, options: [], range: full) { m, _, _ in
                        guard let m = m else { return }
                        let inner = NSIntersectionRange(m.range(at: 1), target)
                        guard inner.length > 0, let sub = rules[lang] else { return }
                        storage.addAttribute(.foregroundColor, value: textColor, range: inner)
                        apply(sub, to: storage, string: string, range: inner, theme: theme)
                    }
                }
            }
        }
        storage.endEditing()
    }

    private static func apply(_ rules: [HighlightRule], to storage: NSTextStorage, string: String,
                              range: NSRange, theme: Theme) {
        for rule in rules {
            let color = theme.color(for: rule.kind)
            rule.regex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
                guard let m = match else { return }
                let r = m.range(at: rule.group)
                if r.location != NSNotFound, r.length > 0 {
                    storage.addAttribute(.foregroundColor, value: color, range: NSIntersectionRange(r, range))
                }
            }
        }
    }
}
