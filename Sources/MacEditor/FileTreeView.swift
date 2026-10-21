import SwiftUI
import AppKit

final class FileNode: Identifiable {
    static let ignoredNames: Set<String> = [".git", ".build", "node_modules", ".DS_Store", ".svn", ".hg"]

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
        let nodes = urls
            .filter { !FileNode.ignoredNames.contains($0.lastPathComponent) }
            .map { FileNode(url: $0) }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        cached = nodes
        return nodes
    }
}

/// Multi-root workspace shared by all windows, persisted in UserDefaults.
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()
    private static let defaultsKey = "workspaceRoots"

    @Published private(set) var roots: [FileNode] = []
    @Published var collapsed: Set<URL> = []
    @Published var hoveredRoot: URL? = nil

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: WorkspaceStore.defaultsKey) ?? []
        var isDir: ObjCBool = false
        roots = paths
            .filter { FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue }
            .map { FileNode(url: URL(fileURLWithPath: $0)) }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(roots.map { $0.url.path }, forKey: WorkspaceStore.defaultsKey)
    }

    func add(_ urls: [URL]) {
        for url in urls where !roots.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            roots.append(FileNode(url: url))
        }
        persist()
    }

    func remove(_ url: URL) {
        roots.removeAll { $0.url == url }
        collapsed.remove(url)
        persist()
    }

    /// Re-reads a root from disk by replacing its node (drops cached children).
    func refresh(_ url: URL) {
        guard let i = roots.firstIndex(where: { $0.url == url }) else { return }
        roots[i] = FileNode(url: url)
    }

    /// Shows a multi-select folder picker; returns true if anything was added.
    @discardableResult
    func chooseFolders() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.t("addFolder")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return false }
        add(panel.urls)
        return true
    }

    func isExpanded(_ url: URL) -> Binding<Bool> {
        Binding(get: { !self.collapsed.contains(url) },
                set: { expanded in
                    if expanded { self.collapsed.remove(url) } else { self.collapsed.insert(url) }
                })
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct FileTreeView: View {
    @ObservedObject var ui: EditorUIState
    @ObservedObject var store = WorkspaceStore.shared
    let theme: Theme
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"

    private func t(_ key: String) -> String { L10n.t(key, uiLanguage) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Text(t("workspace").uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
                .background(DoubleClickZoomZone())
                Button { ui.chooseFolder() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help(t("addFolder"))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)

            if store.roots.isEmpty {
                Color.clear.background(DoubleClickZoomZone())
                Text(t("noFolder")).foregroundColor(.secondary)
                Button(t("chooseFolder")) { ui.chooseFolder() }
                    .padding(.top, 6)
                Color.clear.background(DoubleClickZoomZone())
            } else {
                List {
                    ForEach(store.roots) { root in
                        DisclosureGroup(isExpanded: store.isExpanded(root.url)) {
                            OutlineGroup(root.children ?? [], children: \.children) { node in
                                fileRow(node)
                            }
                        } label: {
                            rootHeader(root)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(theme.swiftUI(\.chrome))
    }

    private func rootHeader(_ root: FileNode) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill").foregroundColor(theme.swiftUI(\.function))
            Text(root.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer()
            if store.hoveredRoot == root.url {
                Button { store.refresh(root.url) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(t("refresh"))
                Button { store.remove(root.url) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help(t("removeFolder"))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { store.hoveredRoot = root.url } else if store.hoveredRoot == root.url { store.hoveredRoot = nil }
        }
        .contextMenu {
            Button(t("revealInFinder")) { WorkspaceStore.reveal(root.url) }
            Button(t("refresh")) { store.refresh(root.url) }
            Divider()
            Button(t("removeFolder")) { store.remove(root.url) }
        }
        .help(root.url.path)
    }

    private func fileRow(_ node: FileNode) -> some View {
        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
            .font(.system(size: 12))
            .lineLimit(1)
            .contentShape(Rectangle())
            .onTapGesture {
                if !node.isDirectory {
                    NSDocumentController.shared.openDocument(withContentsOf: node.url, display: true) { _, _, _ in }
                }
            }
            .contextMenu {
                Button(t("revealInFinder")) { WorkspaceStore.reveal(node.url) }
            }
    }
}
