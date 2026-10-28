import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Per-window UI state (ObservableObject; no SwiftUI macros).
final class EditorUIState: ObservableObject {
    @Published var softWrap: Bool = UserDefaults.standard.object(forKey: "softWrapDefault") as? Bool ?? true
    @Published var showPreview = true
    @Published var showSidebar = !WorkspaceStore.shared.roots.isEmpty
    @Published var showOutline = false
    @Published var showGoToLine = false
    @Published var showFindInFiles = false
    @Published var showInvisibles = false
    @Published var showIndentGuides: Bool = UserDefaults.standard.object(forKey: "showIndentGuides") as? Bool ?? true
    @Published var cursor = CursorPosition()
    /// nil = automatic (extension, then content sniffing)
    @Published var languageOverride: Language? = nil
    @Published var detectedLanguage: Language = .plain
    @Published var wordCount = 0
    @Published var charCount = 0
    @Published var outlineItems: [OutlineItem] = []
    /// "2/5" style find match status; empty when no find string.
    @Published var findMatchLabel = ""

    private var countWork: DispatchWorkItem?
    private var outlineWork: DispatchWorkItem?
    private var findWork: DispatchWorkItem?
    private let fileWatcher = DocumentFileWatcher()
    private var reloadPromptVisible = false

    /// Set by ⇧⌘O when no window was open; the next window shows its sidebar.
    static var pendingShowSidebar = false
    /// Open document then jump to line (Find in Files).
    static var pendingGoTo: (url: URL, line: Int)?

    weak var textView: CodeTextView? {
        didSet { textView?.editorUI = self }
    }
    var fileURL: URL? {
        didSet { setupWatcher() }
    }
    var currentLanguage: Language = .plain
    /// Binding setter used when external reload replaces document text.
    var applyReloadedText: ((String, String.Encoding, LineEnding, Data) -> Void)?

    private var detectWork: DispatchWorkItem?
    private var saveObserver: NSObjectProtocol?

    init() {
        fileWatcher.onChanged = { [weak self] in
            self?.handleExternalChange()
        }
        // Our own saves go through TextDocument.fileWrapper(configuration:), which has no
        // window to target directly, so it broadcasts instead; every window's watcher
        // snoozes itself so a save doesn't trigger its own "changed on disk" prompt.
        saveObserver = NotificationCenter.default.addObserver(
            forName: .documentWillWrite, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.fileWatcher.noteLocalSave()
            // NSDocument saves atomically (write to a temp file, then replace), which
            // retargets the path to a new inode. Our watch is a kqueue on the old file
            // descriptor, so without reopening it here, the watch goes dead after the
            // very first save and later external edits would stop being detected.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let url = self.fileURL else { return }
                self.fileWatcher.watch(url: url)
            }
        }
    }

    deinit {
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
    }

    private func setupWatcher() {
        fileWatcher.noteLocalSave()
        fileWatcher.watch(url: fileURL)
    }

    func noteLocalSave() {
        fileWatcher.noteLocalSave()
    }

    private func handleExternalChange() {
        guard let url = fileURL, !reloadPromptVisible else { return }
        reloadPromptVisible = true
        let alert = NSAlert()
        alert.messageText = L10n.t("fileChangedTitle")
        alert.informativeText = L10n.f("fileChangedBody", L10n.currentPreference, url.lastPathComponent)
        alert.addButton(withTitle: L10n.t("reload"))
        alert.addButton(withTitle: L10n.t("keepEditing"))
        let response = alert.runModal()
        reloadPromptVisible = false
        if response == .alertFirstButtonReturn {
            reloadFromDisk()
        } else {
            // Keep watching; user may save over later
            fileWatcher.watch(url: url)
        }
    }

    func reloadFromDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let (decoded, enc) = TextDocument.decode(data, pathExtension: url.pathExtension)
        let normalized = TextDocument.normalizeLineEndings(decoded)
        applyReloadedText?(normalized.text, enc, normalized.ending, data)
        fileWatcher.noteLocalSave()
        fileWatcher.watch(url: url)
        if let tv = textView {
            tv.rebuildFolds()
        }
        scheduleOutline(normalized.text, language: currentLanguage, immediate: true)
        updateCounts(normalized.text, immediate: true)
    }

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

    func scheduleOutline(_ text: String, language: Language, immediate: Bool = false) {
        outlineWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let items = OutlineBuilder.build(text: text, language: language)
            if self.outlineItems != items { self.outlineItems = items }
        }
        outlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.5), execute: work)
    }

    func updateFindMatchStatus(text: String, caret: Int) {
        findWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let q = FindMatchCounter.findPasteboardString() else {
                if !self.findMatchLabel.isEmpty { self.findMatchLabel = "" }
                return
            }
            if let (cur, total) = FindMatchCounter.status(in: text, query: q, caret: caret) {
                let label = L10n.f("findMatch", L10n.currentPreference, cur, total)
                if self.findMatchLabel != label { self.findMatchLabel = label }
            } else {
                if !self.findMatchLabel.isEmpty { self.findMatchLabel = "" }
            }
        }
        findWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
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

    func consumePendingGoTo(matching url: URL?) {
        guard let pending = EditorUIState.pendingGoTo else { return }
        guard let url, pending.url.standardizedFileURL == url.standardizedFileURL else { return }
        EditorUIState.pendingGoTo = nil
        let line = pending.line
        DispatchQueue.main.async { [weak self] in
            self?.goTo(line: line)
        }
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

    func syncEditorChrome() {
        guard let tv = textView else { return }
        tv.showInvisibles = showInvisibles
        tv.showIndentGuides = showIndentGuides
        tv.needsDisplay = true
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
