import SwiftUI
import AppKit

struct ContentView: View {
    @Binding var document: TextDocument
    let fileURL: URL?

    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("tabWidth") private var tabWidth: Int = 4
    @AppStorage("theme") private var themePreference: String = "auto"
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"
    @AppStorage("showIndentGuides") private var showIndentGuidesPref: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var ui = EditorUIState()

    private var extensionLanguage: Language { Language.detect(url: fileURL) }
    private var language: Language {
        if let o = ui.languageOverride { return o }
        let ext = extensionLanguage
        return ext != .plain ? ext : ui.detectedLanguage
    }
    private var isMarkdown: Bool { language == .markdown }
    private var theme: Theme { Theme.resolve(themePreference, systemIsDark: colorScheme == .dark) }
    private var forcedScheme: ColorScheme? {
        guard let t = Theme.all.first(where: { $0.id == themePreference }) else { return nil }
        return t.isDark ? .dark : .light
    }
    private func t(_ key: String) -> String { L10n.t(key, uiLanguage) }

    var body: some View {
        HSplitView {
            if ui.showSidebar {
                FileTreeView(ui: ui, theme: theme)
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 400)
            }
            mainArea.frame(minWidth: 360)
            if ui.showOutline {
                OutlineView(ui: ui, theme: theme)
                    .frame(minWidth: 140, idealWidth: 180, maxWidth: 320)
            }
        }
        .background(WindowConfigurator(background: theme.ns(\.chrome)))
        .frame(minWidth: 520, minHeight: 320)
        .preferredColorScheme(forcedScheme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { ui.showSidebar.toggle() } label: {
                    Label(t("sidebar"), systemImage: "sidebar.left")
                }
                .help(t("sidebarHelp"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { ui.showOutline.toggle() } label: {
                    Label(t("outline"), systemImage: "list.bullet.indent")
                }
                .help(t("outlineHelp"))
                Button { ui.softWrap.toggle() } label: {
                    Label(t("softWrap"), systemImage: ui.softWrap ? "text.alignleft" : "arrow.right.to.line")
                }
                .help(t("softWrapHelp"))
                if isMarkdown {
                    Button { ui.showPreview.toggle() } label: {
                        Label(t("preview"), systemImage: ui.showPreview ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    }
                    .help(t("previewHelp"))
                }
            }
        }
        .sheet(isPresented: $ui.showGoToLine) {
            GoToLineSheet(ui: ui, maxLine: ui.lineCount)
        }
        .sheet(isPresented: $ui.showFindInFiles) {
            FindInFilesSheet(ui: ui, theme: theme)
        }
        .focusedSceneValue(\.softWrap, $ui.softWrap)
        .focusedSceneValue(\.showPreview, $ui.showPreview)
        .focusedSceneValue(\.uiState, ui)
        .onAppear {
            ui.fileURL = fileURL
            ui.showIndentGuides = showIndentGuidesPref
            ui.applyReloadedText = { text, enc, ending, data in
                document.text = text
                document.encoding = enc
                document.lineEnding = ending
                document.originalData = data
            }
            if EditorUIState.pendingShowSidebar {
                EditorUIState.pendingShowSidebar = false
                ui.showSidebar = true
            }
            ui.scheduleDetect(document.text, immediate: true)
            ui.updateCounts(document.text, immediate: true)
            ui.scheduleOutline(document.text, language: language, immediate: true)
            ui.consumePendingGoTo(matching: fileURL)
        }
        .onChange(of: document.text) { newValue in
            if extensionLanguage == .plain { ui.scheduleDetect(newValue) }
            ui.updateCounts(newValue)
            ui.scheduleOutline(newValue, language: language)
        }
        .onChange(of: fileURL) { newValue in
            ui.fileURL = newValue
            ui.consumePendingGoTo(matching: newValue)
        }
        .onChange(of: language) { newValue in
            ui.currentLanguage = newValue
            ui.scheduleOutline(document.text, language: newValue, immediate: true)
        }
        .onChange(of: ui.showIndentGuides) { newValue in
            showIndentGuidesPref = newValue
            ui.syncEditorChrome()
        }
        .onChange(of: ui.showInvisibles) { _ in ui.syncEditorChrome() }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            if isMarkdown && ui.showPreview {
                HSplitView {
                    editor.frame(minWidth: 220)
                    MarkdownPreview(markdown: document.text, theme: theme).frame(minWidth: 220)
                }
            } else {
                editor
            }
            Rectangle().fill(theme.swiftUI(\.separator)).frame(height: 1)
            StatusBar(ui: ui, theme: theme, language: language, document: $document)
        }
        .background(theme.swiftUI(\.background))
    }

    private var editor: some View {
        let state = ui
        return EditorTextView(
            text: $document.text,
            language: language,
            theme: theme,
            fontSize: CGFloat(fontSize),
            tabWidth: tabWidth,
            softWrap: ui.softWrap,
            showInvisibles: ui.showInvisibles,
            showIndentGuides: ui.showIndentGuides,
            ui: state
        )
        .onAppear { state.currentLanguage = language }
        .onChange(of: language) { newValue in state.currentLanguage = newValue }
    }
}

struct OutlineView: View {
    @ObservedObject var ui: EditorUIState
    let theme: Theme
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"

    private func t(_ key: String) -> String { L10n.t(key, uiLanguage) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("outline").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            if ui.outlineItems.isEmpty {
                Text(t("outlineEmpty"))
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
                Spacer()
            } else {
                List(ui.outlineItems) { item in
                    Text(String(repeating: "  ", count: item.depth) + item.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture { ui.goTo(line: item.line) }
                }
                .listStyle(.sidebar)
            }
        }
        .background(theme.swiftUI(\.chrome))
    }
}

struct GoToLineSheet: View {
    @ObservedObject var ui: EditorUIState
    let maxLine: Int
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"
    @StateObject private var model = GoToLineModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.f("goToLinePrompt", uiLanguage, maxLine))
            TextField("", text: $model.text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(go)
            HStack {
                Spacer()
                Button(L10n.t("cancel", uiLanguage)) { ui.showGoToLine = false }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("go", uiLanguage), action: go)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func go() {
        let n = Int(model.text.trimmingCharacters(in: .whitespaces)) ?? 1
        ui.showGoToLine = false
        let target = max(1, min(n, maxLine))
        let state = ui
        DispatchQueue.main.async { state.goTo(line: target) }
    }
}

final class GoToLineModel: ObservableObject {
    @Published var text = ""
}

struct StatusBar: View {
    @ObservedObject var ui: EditorUIState
    let theme: Theme
    let language: Language
    @Binding var document: TextDocument
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"

    private func t(_ key: String) -> String { L10n.t(key, uiLanguage) }

    private var encodingChoices: [(String, String.Encoding)] {
        [
            (t("encUTF8"), .utf8),
            (t("encGB18030"), .gb18030),
            (t("encISO88591"), .isoLatin1),
            (t("encUTF16"), .utf16LittleEndian),
        ]
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(L10n.f("lnCol", uiLanguage, ui.cursor.line, ui.cursor.column))
            Text(L10n.f("counts", uiLanguage, ui.wordCount, ui.charCount))
            if !ui.findMatchLabel.isEmpty {
                Text(ui.findMatchLabel)
            }
            Spacer()
            Text(L10n.t(ui.softWrap ? "wrap" : "noWrap", uiLanguage))
            encodingMenu
            Text(document.lineEnding.rawValue)
            Menu {
                Button((ui.languageOverride == nil ? "✓ " : "") + L10n.t("autoDetect", uiLanguage)) {
                    ui.languageOverride = nil
                }
                Divider()
                ForEach(Language.allCases, id: \.self) { lang in
                    Button((ui.languageOverride == lang ? "✓ " : "") + lang.rawValue) {
                        ui.languageOverride = lang
                    }
                }
            } label: {
                Text(language.rawValue)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundColor(theme.swiftUI(\.gutterActiveText).opacity(0.75))
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(theme.swiftUI(\.chrome))
    }

    private var encodingMenu: some View {
        Menu {
            Text(t("reopenWithEncoding"))
            Divider()
            ForEach(encodingChoices, id: \.0) { item in
                let selected = document.encoding.displayName == item.1.displayName
                    || (document.encoding == item.1)
                Button((selected ? "✓ " : "") + item.0) {
                    reopen(as: item.1)
                }
            }
        } label: {
            Text(document.encoding.displayName)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(t("encoding"))
    }

    private func reopen(as encoding: String.Encoding) {
        document.reopen(with: encoding, fileURL: ui.fileURL)
        ui.updateCounts(document.text, immediate: true)
        ui.scheduleDetect(document.text, immediate: true)
        ui.scheduleOutline(document.text, language: language, immediate: true)
    }
}

/// Gives the hosting window a transparent, themed titlebar.
struct WindowConfigurator: NSViewRepresentable {
    var background: NSColor

    final class Probe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let w = window { onWindow?(w) }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let v = Probe()
        let bg = background
        v.onWindow = { w in WindowConfigurator.configure(w, background: bg) }
        return v
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        let bg = background
        nsView.onWindow = { w in WindowConfigurator.configure(w, background: bg) }
        if let w = nsView.window { WindowConfigurator.configure(w, background: bg) }
    }

    static func configure(_ w: NSWindow, background: NSColor) {
        w.titlebarAppearsTransparent = true
        w.backgroundColor = background
        w.tabbingMode = .preferred
    }
}
