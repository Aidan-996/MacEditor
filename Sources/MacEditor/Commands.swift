import SwiftUI
import AppKit

struct SoftWrapKey: FocusedValueKey { typealias Value = Binding<Bool> }
struct ShowPreviewKey: FocusedValueKey { typealias Value = Binding<Bool> }
struct UIStateKey: FocusedValueKey { typealias Value = EditorUIState }

extension FocusedValues {
    var softWrap: Binding<Bool>? {
        get { self[SoftWrapKey.self] }
        set { self[SoftWrapKey.self] = newValue }
    }
    var showPreview: Binding<Bool>? {
        get { self[ShowPreviewKey.self] }
        set { self[ShowPreviewKey.self] = newValue }
    }
    var uiState: EditorUIState? {
        get { self[UIStateKey.self] }
        set { self[UIStateKey.self] = newValue }
    }
}

/// Sends an NSTextFinder action to the first responder (the focused NSTextView).
func sendFinderAction(_ action: NSTextFinder.Action) {
    let item = NSMenuItem()
    item.tag = action.rawValue
    NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
}

func sendEditorAction(_ selector: Selector) {
    NSApp.sendAction(selector, to: nil, from: nil)
}

struct EditorCommands: Commands {
    @FocusedBinding(\.softWrap) var softWrap
    @FocusedBinding(\.showPreview) var showPreview
    @FocusedValue(\.uiState) var ui
    @AppStorage("uiLanguage") var uiLanguage: String = "system"

    private func t(_ key: String) -> String { L10n.t(key, uiLanguage) }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(t("openFolder")) {
                if let ui = ui { ui.chooseFolder() } else { AppDelegate.openFolderInNewWindow() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .importExport) {
            Button(t("exportHTML")) { ui?.exportHTML() }
                .disabled(ui == nil || ui?.currentLanguage != .markdown)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button(t("find")) { sendFinderAction(.showFindInterface) }
                .keyboardShortcut("f", modifiers: .command)
            Button(t("findReplace")) { sendFinderAction(.showReplaceInterface) }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button(t("findNext")) {
                sendFinderAction(.nextMatch)
                refreshFindLabel()
            }
                .keyboardShortcut("g", modifiers: .command)
            Button(t("findPrev")) {
                sendFinderAction(.previousMatch)
                refreshFindLabel()
            }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button(t("useSelection")) { sendFinderAction(.setSearchString) }
                .keyboardShortcut("e", modifiers: .command)
            Button(t("findInFiles")) {
                ui?.showSidebar = true
                ui?.showFindInFiles = true
            }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(ui == nil)
            Divider()
            Button(t("selectNextOccurrence")) { sendEditorAction(#selector(CodeTextView.selectNextOccurrence(_:))) }
                .keyboardShortcut("d", modifiers: .command)
            Button(t("addCursorBelow")) { sendEditorAction(#selector(CodeTextView.addCursorBelow(_:))) }
                .keyboardShortcut(.downArrow, modifiers: [.control, .shift])
            Button(t("addCursorAbove")) { sendEditorAction(#selector(CodeTextView.addCursorAbove(_:))) }
                .keyboardShortcut(.upArrow, modifiers: [.control, .shift])
            Divider()
            Button(t("fold")) { sendEditorAction(#selector(CodeTextView.foldCurrent(_:))) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button(t("unfoldAll")) { sendEditorAction(#selector(CodeTextView.unfoldAll(_:))) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button(t("goToLine")) { ui?.showGoToLine = true }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(ui == nil)
            Button(t("toggleComment")) { sendEditorAction(#selector(CodeTextView.toggleComment(_:))) }
                .keyboardShortcut("/", modifiers: .command)
            Button(t("duplicateLine")) { sendEditorAction(#selector(CodeTextView.duplicateLine(_:))) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button(t("moveUp")) { sendEditorAction(#selector(CodeTextView.moveLineUp(_:))) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button(t("moveDown")) { sendEditorAction(#selector(CodeTextView.moveLineDown(_:))) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
        CommandGroup(after: .toolbar) {
            Button(t("toggleSidebar")) { ui?.showSidebar.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(ui == nil)
            Button(t("toggleOutline")) { ui?.showOutline.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(ui == nil)
            Button(t("toggleSoftWrap")) {
                if let v = softWrap { softWrap = !v }
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(softWrap == nil)
            Button(t("togglePreview")) {
                if let v = showPreview { showPreview = !v }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(showPreview == nil)
            Button(t("toggleInvisibles")) { ui?.showInvisibles.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(ui == nil)
            Button(t("toggleIndentGuides")) { ui?.showIndentGuides.toggle() }
                .disabled(ui == nil)
            Divider()
        }
    }

    private func refreshFindLabel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let ui = ui, let tv = ui.textView else { return }
            ui.updateFindMatchStatus(text: tv.string, caret: tv.selectedRange().location)
        }
    }
}
