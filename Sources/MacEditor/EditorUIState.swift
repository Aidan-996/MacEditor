import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Per-window UI state (ObservableObject; no SwiftUI macros).
final class EditorUIState: ObservableObject {
    @Published var softWrap: Bool = UserDefaults.standard.object(forKey: "softWrapDefault") as? Bool ?? true
    @Published var showPreview = true
    @Published var showSidebar = !WorkspaceStore.shared.roots.isEmpty
    @Published var showGoToLine = false
    @Published var cursor = CursorPosition()
    /// nil = automatic (extension, then content sniffing)
    @Published var languageOverride: Language? = nil
    @Published var detectedLanguage: Language = .plain
    @Published var wordCount = 0
    @Published var charCount = 0

    private var countWork: DispatchWorkItem?
    /// Set by ⇧⌘O when no window was open; the next window shows its sidebar.
    static var pendingShowSidebar = false

    weak var textView: CodeTextView?
    var fileURL: URL?
    var currentLanguage: Language = .plain

    private var detectWork: DispatchWorkItem?

    /// Debounced language sniffing.
    func scheduleDetect(_ text: String, immediate: Bool = false) {
        detectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let lang = Language.detect(content: text)
            if self.detectedLanguage != lang { self.detectedLanguage = lang }
        }
        detectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.6), execute: work)
    }

    /// Debounced word / character counts.
    func updateCounts(_ text: String, immediate: Bool = false) {
        countWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let (w, c) = TextStats.count(text)
            if self.wordCount != w { self.wordCount = w }
            if self.charCount != c { self.charCount = c }
        }
        countWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.25), execute: work)
    }

    func chooseFolder() {
        if WorkspaceStore.shared.chooseFolders() { showSidebar = true }
    }

    func goTo(line: Int) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        var current = 1
        var loc = 0
        while current < line && loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(r)
            current += 1
        }
        let target = NSRange(location: min(loc, ns.length), length: 0)
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(target)
        tv.scrollRangeToVisible(target)
        let lineRange = ns.lineRange(for: target)
        if lineRange.length > 0 { tv.showFindIndicator(for: lineRange) }
    }

    var lineCount: Int {
        guard let tv = textView else { return 1 }
        return tv.string.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    func exportHTML() {
        guard let tv = textView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = base + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = MarkdownRenderer.html(tv.string, theme: .githubLight)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("exportFailed")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.t("ok"))
            alert.runModal()
        }
    }
}

enum TextStats {
    static func isCJK(_ v: UInt32) -> Bool {
        switch v {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF,
             0xF900...0xFAFF, 0xFF66...0xFF9F, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    /// chars = number of Characters (grapheme clusters, newlines included);
    /// words = each CJK character counts as one word, plus runs of other letters/digits.
    static func count(_ text: String) -> (words: Int, chars: Int) {
        var words = 0
        var inRun = false
        let alnum = CharacterSet.alphanumerics
        for scalar in text.unicodeScalars {
            if isCJK(scalar.value) {
                words += 1
                inRun = false
            } else if alnum.contains(scalar) || scalar == "_" || scalar == "'" && inRun {
                if !inRun { words += 1; inRun = true }
            } else {
                inRun = false
            }
        }
        return (words, text.count)
    }
}
