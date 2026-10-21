import AppKit
import SwiftUI

enum TokenKind {
    case keyword, string, comment, number, type, attribute, tag, heading, function, punctuation
}

struct Theme: Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let background: UInt32
    let chrome: UInt32          // gutter / status bar / window
    let gutterText: UInt32
    let gutterActiveText: UInt32
    let currentLine: UInt32
    let selection: UInt32
    let cursor: UInt32
    let text: UInt32
    let keyword: UInt32
    let string: UInt32
    let comment: UInt32
    let number: UInt32
    let type: UInt32
    let attribute: UInt32
    let tag: UInt32
    let heading: UInt32
    let function: UInt32
    let bracket: UInt32
    let separator: UInt32

    static func ns(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    static func css(_ hex: UInt32) -> String { String(format: "#%06X", hex) }

    func ns(_ kp: KeyPath<Theme, UInt32>) -> NSColor { Theme.ns(self[keyPath: kp]) }
    func swiftUI(_ kp: KeyPath<Theme, UInt32>) -> Color { Color(nsColor: ns(kp)) }

    func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword: return ns(\.keyword)
        case .string: return ns(\.string)
        case .comment: return ns(\.comment)
        case .number: return ns(\.number)
        case .type: return ns(\.type)
        case .attribute: return ns(\.attribute)
        case .tag: return ns(\.tag)
        case .heading: return ns(\.heading)
        case .function: return ns(\.function)
        case .punctuation: return ns(\.gutterText)
        }
    }

    static let oneDark = Theme(
        id: "oneDark", name: "One Dark", isDark: true,
        background: 0x282C34, chrome: 0x21252B, gutterText: 0x4B5263, gutterActiveText: 0xABB2BF,
        currentLine: 0x2C313C, selection: 0x3E4451, cursor: 0x528BFF, text: 0xABB2BF,
        keyword: 0xC678DD, string: 0x98C379, comment: 0x7F848E, number: 0xD19A66, type: 0xE5C07B,
        attribute: 0xD19A66, tag: 0xE06C75, heading: 0xE06C75, function: 0x61AFEF,
        bracket: 0x4A5263, separator: 0x181A1F)

    static let oneLight = Theme(
        id: "oneLight", name: "One Light", isDark: false,
        background: 0xFAFAFA, chrome: 0xEFEFF0, gutterText: 0xA0A1A7, gutterActiveText: 0x383A42,
        currentLine: 0xF0F0F1, selection: 0xDCDCE0, cursor: 0x526FFF, text: 0x383A42,
        keyword: 0xA626A4, string: 0x50A14F, comment: 0xA0A1A7, number: 0x986801, type: 0xC18401,
        attribute: 0x986801, tag: 0xE45649, heading: 0xE45649, function: 0x4078F2,
        bracket: 0xD3D3DA, separator: 0xDBDBDC)

    static let tokyoNight = Theme(
        id: "tokyoNight", name: "Tokyo Night", isDark: true,
        background: 0x1A1B26, chrome: 0x16161E, gutterText: 0x3B4261, gutterActiveText: 0xC0CAF5,
        currentLine: 0x1F2335, selection: 0x33467C, cursor: 0xC0CAF5, text: 0xC0CAF5,
        keyword: 0xBB9AF7, string: 0x9ECE6A, comment: 0x565F89, number: 0xFF9E64, type: 0x2AC3DE,
        attribute: 0xE0AF68, tag: 0xF7768E, heading: 0x7AA2F7, function: 0x7AA2F7,
        bracket: 0x3B4261, separator: 0x101014)

    static let githubLight = Theme(
        id: "githubLight", name: "GitHub Light", isDark: false,
        background: 0xFFFFFF, chrome: 0xF6F8FA, gutterText: 0x8C959F, gutterActiveText: 0x1F2328,
        currentLine: 0xF6F8FA, selection: 0xB6E3FF, cursor: 0x0969DA, text: 0x1F2328,
        keyword: 0xCF222E, string: 0x0A3069, comment: 0x6E7781, number: 0x0550AE, type: 0x953800,
        attribute: 0x0550AE, tag: 0x116329, heading: 0x0550AE, function: 0x8250DF,
        bracket: 0xD0D7DE, separator: 0xD0D7DE)

    static let all: [Theme] = [.oneDark, .oneLight, .tokyoNight, .githubLight]

    /// preference: "auto" or a theme id.
    static func resolve(_ preference: String, systemIsDark: Bool) -> Theme {
        if let t = all.first(where: { $0.id == preference }) { return t }
        return systemIsDark ? .oneDark : .oneLight
    }
}
