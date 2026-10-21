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

    init(text: String = "") {
        self.text = text
        self.encoding = .utf8
        self.lineEnding = .lf
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let (decoded, enc) = TextDocument.decode(data)
        self.encoding = enc
        if decoded.contains("\r\n") {
            self.lineEnding = .crlf
            self.text = decoded.replacingOccurrences(of: "\r\n", with: "\n")
        } else {
            self.lineEnding = .lf
            self.text = decoded
        }
    }

    static func decode(_ data: Data) -> (String, String.Encoding) {
        var bytes = data
        // Strip UTF-8 BOM
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let s = String(data: bytes, encoding: .utf8) { return (s, .utf8) }
        if let s = String(data: data, encoding: .gb18030) { return (s, .gb18030) }
        return (String(decoding: data, as: UTF8.self), .utf8)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var out = text
        if lineEnding == .crlf { out = out.replacingOccurrences(of: "\n", with: "\r\n") }
        let data = out.data(using: encoding) ?? Data(out.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
