import SwiftUI
import AppKit

final class FileNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    private var cached: [FileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    /// nil for files (so OutlineGroup shows no disclosure triangle); loaded lazily for folders.
    var children: [FileNode]? {
        guard isDirectory else { return nil }
        if let c = cached { return c }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let nodes = urls.map { FileNode(url: $0) }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        cached = nodes
        return nodes
    }
}

struct FileTreeView: View {
    @ObservedObject var ui: EditorUIState
    let theme: Theme
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"

    var body: some View {
        VStack(spacing: 0) {
            if let root = ui.folderRoot {
                HStack {
                    Text(root.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button { ui.folderRoot = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help(L10n.t("closeFolder", uiLanguage))
                }
                .padding(.horizontal, 10).frame(height: 28)
                List {
                    OutlineGroup(root.children ?? [], children: \.children) { node in
                        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !node.isDirectory {
                                    NSDocumentController.shared.openDocument(withContentsOf: node.url, display: true) { _, _, _ in }
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            } else {
                Spacer()
                Text(L10n.t("noFolder", uiLanguage)).foregroundColor(.secondary)
                Button(L10n.t("chooseFolder", uiLanguage)) { ui.chooseFolder() }
                    .padding(.top, 6)
                Spacer()
            }
        }
        .background(theme.swiftUI(\.chrome))
    }
}
