import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var autosaveTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no bundle): make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WindowDoubleClick.install()
        NSDocumentController.shared.autosavingDelay = 5   // NSDocument autosave-in-place / crash recovery

        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            guard UserDefaults.standard.bool(forKey: "autosaveEnabled") else { return }
            for doc in NSDocumentController.shared.documents where doc.isDocumentEdited && doc.fileURL != nil {
                doc.save(nil)
            }
        }
    }

    /// ⇧⌘O with no window open: add folders to the workspace, then open a window showing the sidebar.
    static func openFolderInNewWindow() {
        guard WorkspaceStore.shared.chooseFolders() else { return }
        EditorUIState.pendingShowSidebar = true
        NSDocumentController.shared.newDocument(nil)
    }
}

@main
struct MacEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands { EditorCommands() }
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))

        Settings {
            PreferencesView()
        }
    }
}
