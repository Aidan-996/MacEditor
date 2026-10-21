import SwiftUI
import UniformTypeIdentifiers
import CoreFoundation

enum LineEnding: String {
    case lf = "LF"
    case crlf = "CRLF"
}

extension String.Encoding {
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .gb18030: return "GB18030"
        case .isoLatin1: return "ISO-8859-1"
        case .utf16, .utf16LittleEndian, .utf16BigEndian: return "UTF-16"
        default: return String.localizedName(of: self)
        }
    }
}

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText, .sourceCode, .json, .markdownText, .data]
    }
    static var writableContentTypes: [UTType] {
        [.plainText, .sourceCode, .json, .markdownText, .data]
    }

    /// Text is held internally with "\n" line endings.
    var text: String
    var encoding: String.Encoding
    var lineEnding: LineEnding
    /// Raw bytes from the last open / reload; used by "Reopen with Encoding".
    var originalData: Data?

    init(text: String = "") {
        self.text = text
        self.encoding = .utf8
        self.lineEnding = .lf
        self.originalData = nil
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.originalData = data
        let (decoded, enc) = TextDocument.decode(data)
        self.encoding = enc
        let normalized = TextDocument.normalizeLineEndings(decoded)
        self.lineEnding = normalized.ending
        self.text = normalized.text
    }

    // MARK: - Encoding detection

    /// Decode file bytes without ever using lossy `String(decoding:as:UTF8.self)`.
    ///
    /// Heuristic (when no BOM):
    /// 1. Null-byte pattern → UTF-16 LE/BE.
    /// 2. Strict UTF-8; if invalid → try GB18030.
    /// 3. If both strict-succeed: prefer GB18030 when the byte stream looks like GBK
    ///    (high density of lead 0x81–0xFE + trail pairs that are rare/invalid as UTF-8),
    ///    or when UTF-8 text looks like mojibake (many Ã/Â) while GB18030 yields more CJK.
    /// 4. Last resort: ISO-8859-1 (maps every byte) instead of replacement UTF-8.
    static func decode(_ data: Data, pathExtension: String? = nil) -> (String, String.Encoding) {
        if data.isEmpty { return ("", .utf8) }

        // --- BOM ---
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = data.dropFirst(3)
            if let s = String(data: Data(body), encoding: .utf8) {
                return (s, .utf8)
            }
        }
        if data.starts(with: [0xFF, 0xFE]) {
            if let s = String(data: data, encoding: .utf16LittleEndian) {
                return (s, .utf16LittleEndian)
            }
        }
        if data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: .utf16BigEndian) {
                return (s, .utf16BigEndian)
            }
        }

        // --- UTF-16 without BOM (lots of NULs) ---
        if looksLikeUTF16(data) {
            if let s = String(data: data, encoding: .utf16LittleEndian), !s.isEmpty {
                return (s, .utf16LittleEndian)
            }
            if let s = String(data: data, encoding: .utf16BigEndian), !s.isEmpty {
                return (s, .utf16BigEndian)
            }
        }

        let utf8 = String(data: data, encoding: .utf8)   // strict; nil if invalid
        let gb = String(data: data, encoding: .gb18030)

        switch (utf8, gb) {
        case let (u?, nil):
            return (u, .utf8)
        case let (nil, g?):
            return (g, .gb18030)
        case let (u?, g?):
            if shouldPreferGB18030(utf8: u, gb: g, data: data, pathExtension: pathExtension) {
                return (g, .gb18030)
            }
            return (u, .utf8)
        case (nil, nil):
            // Never use lossy UTF-8 — that produces 乱码 for GBK CSVs.
            if let latin = String(data: data, encoding: .isoLatin1) {
                return (latin, .isoLatin1)
            }
            return ("", .utf8)
        }
    }

    /// Force-decode with a chosen encoding (strips matching BOM when present).
    static func decode(_ data: Data, as encoding: String.Encoding) -> String? {
        var bytes = data
        switch encoding {
        case .utf8:
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = Data(bytes.dropFirst(3)) }
        case .utf16LittleEndian, .utf16:
            // String handles BOM for utf16; keep as-is for LE/BE specifics
            break
        default:
            break
        }
        return String(data: bytes, encoding: encoding)
    }

    /// Reinterpret `originalData` (or re-read `fileURL`) with `encoding`.
    mutating func reopen(with encoding: String.Encoding, fileURL: URL?) {
        let data: Data?
        if let originalData {
            data = originalData
        } else if let fileURL {
            data = try? Data(contentsOf: fileURL)
            if let data { originalData = data }
        } else {
            data = nil
        }
        guard let data, let decoded = TextDocument.decode(data, as: encoding) else { return }
        let normalized = TextDocument.normalizeLineEndings(decoded)
        self.encoding = encoding
        self.lineEnding = normalized.ending
        self.text = normalized.text
    }

    static func normalizeLineEndings(_ decoded: String) -> (text: String, ending: LineEnding) {
        if decoded.contains("\r\n") {
            return (decoded.replacingOccurrences(of: "\r\n", with: "\n"), .crlf)
        }
        return (decoded, .lf)
    }

    // MARK: - Heuristics

    private static func looksLikeUTF16(_ data: Data) -> Bool {
        guard data.count >= 4, data.count % 2 == 0 else { return false }
        var nulls = 0
        // Sample up to 4 KB
        let n = min(data.count, 4096)
        data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self)
            for i in 0..<n where buf[i] == 0 { nulls += 1 }
        }
        return Double(nulls) / Double(n) > 0.1
    }

    /// True when byte pairs look like GBK/GB18030 more than UTF-8.
    private static func gbkByteDensity(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        var hits = 0
        var i = 0
        let bytes = [UInt8](data.prefix(8192))
        while i < bytes.count {
            let b = bytes[i]
            // GBK lead byte 0x81–0xFE, trail 0x40–0x7E or 0x80–0xFE
            if b >= 0x81 && b <= 0xFE, i + 1 < bytes.count {
                let t = bytes[i + 1]
                if (t >= 0x40 && t <= 0x7E) || (t >= 0x80 && t <= 0xFE) {
                    // UTF-8 never uses 0x80–0xBF as a lead; a high lead+trail pair
                    // that is not a well-formed UTF-8 2/3-byte sequence counts as GBK-ish.
                    if !isUTF8LeadTrail(b, t) { hits += 2 }
                    i += 2
                    continue
                }
            }
            i += 1
        }
        return Double(hits) / Double(max(bytes.count, 1))
    }

    private static func isUTF8LeadTrail(_ b: UInt8, _ t: UInt8) -> Bool {
        // 2-byte UTF-8: 110xxxxx 10xxxxxx
        if b >= 0xC2 && b <= 0xDF { return (t & 0xC0) == 0x80 }
        return false
    }

    private static func cjkRatio(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        let sample = s.prefix(8000)
        var cjk = 0
        var total = 0
        for ch in sample {
            total += 1
            for scalar in ch.unicodeScalars {
                if TextStats.isCJK(scalar.value) { cjk += 1; break }
            }
        }
        return total == 0 ? 0 : Double(cjk) / Double(total)
    }

    private static func mojibakeScore(_ s: String) -> Double {
        // Classic UTF-8-read-as-Latin1 / GBK-read-as-UTF-8 markers
        let sample = s.prefix(8000)
        guard !sample.isEmpty else { return 0 }
        var bad = 0
        for ch in sample {
            if ch == "\u{FFFD}" || ch == "Ã" || ch == "Â" || ch == "å" || ch == "æ" || ch == "é" {
                bad += 1
            }
        }
        return Double(bad) / Double(sample.count)
    }

    private static func replacementCount(_ s: String) -> Int {
        s.unicodeScalars.filter { $0 == "\u{FFFD}" }.count
    }

    private static func shouldPreferGB18030(utf8 u: String, gb g: String, data: Data, pathExtension: String?) -> Bool {
        let uRepl = replacementCount(u)
        let gRepl = replacementCount(g)
        if gRepl < uRepl { return true }
        if uRepl < gRepl { return false }

        let density = gbkByteDensity(data)
        let uMojibake = mojibakeScore(u)
        let gCJK = cjkRatio(g)
        let uCJK = cjkRatio(u)

        let ext = pathExtension?.lowercased()
        let textLike = ext == nil || ext == "csv" || ext == "tsv" || ext == "txt" || ext == "log"

        // Strong GBK byte pattern
        if density > 0.08 && gCJK >= uCJK { return true }

        // Mojibake UTF-8 vs readable CJK under GB18030 (common for Excel CSVs)
        if textLike && uMojibake > 0.02 && gCJK > uCJK && gCJK > 0.05 { return true }
        if textLike && gCJK > 0.15 && uCJK < 0.05 && density > 0.03 { return true }

        return false
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var out = text
        if lineEnding == .crlf { out = out.replacingOccurrences(of: "\n", with: "\r\n") }
        let data = out.data(using: encoding) ?? Data(out.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
