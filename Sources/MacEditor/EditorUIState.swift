import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Per-window UI state (ObservableObject; no SwiftUI macros).
final class EditorUIState: ObservableObject {
    @Published var softWrap: Bool = UserDefaults.standard.object(forKey: "softWrapDefault") as? Bool ?? true
    @Published var showPreview = true
    @Published var showSidebar = false
    @Published var showGoToLine = false
    @Published var cursor = CursorPosition()
    /// nil = automatic (extension, then content sniffing)
    @Published var languageOverride: Language? = nil
    @Published var detectedLanguage: Language = .plain
    @Published var wordCount = 0
    @Published var charCount = 0
    @Published var folderRoot: FileNode? = nil

    /// Folder chosen via ⇧⌘O while no window was open; consumed by the next window.
    static var pendingFolder: URL?

    weak var textView: CodeTextView?
    var fileURL: URL?
    var currentLanguage: Language = .plain

    private var detectWork: DispatchWorkItem?

    /// Debounced: language sniffing + word/char counts.
    func scheduleAnalysis(_ text: String, sniff: Bool, immediate: Bool = false) {
        detectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if sniff {
                let lang = Language.detect(content: text)
                if self.detectedLanguage != lang { self.detectedLanguage = lang }
            }
            var words = 0
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in
                words += 1
            }
            self.wordCount = words
            self.charCount = text.count
        }
        detectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.5), execute: work)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("openFolder")
        if panel.runModal() == .OK, let url = panel.url {
            folderRoot = FileNode(url: url)
            showSidebar = true
        }
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
