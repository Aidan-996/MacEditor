import SwiftUI
import AppKit
import CoreServices

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

/// Watches workspace root folders via FSEvents and refreshes the tree on changes.
final class WorkspaceWatcher {
    private var stream: FSEventStreamRef?
    private var paths: [String] = []
    private let onChange: ([String]) -> Void

    init(onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
    }

    func setPaths(_ newPaths: [String]) {
        let normalized = newPaths.map { ($0 as NSString).standardizingPath }.sorted()
        guard normalized != paths else { return }
        stop()
        paths = normalized
        guard !paths.isEmpty else { return }
        start()
    }

    private func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<WorkspaceWatcher>.fromOpaque(info).takeUnretainedValue()
            // With UseCFTypes, eventPaths is a CFArray of CFString paths.
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            var changed: [String] = []
            let count = min(CFArrayGetCount(cfArray), numEvents)
            for i in 0..<count {
                let value = CFArrayGetValueAtIndex(cfArray, i)
                let path = Unmanaged<CFString>.fromOpaque(value!).takeUnretainedValue() as String
                changed.append(path)
            }
            DispatchQueue.main.async { watcher.onChange(changed) }
        }
        let cfPaths = paths as CFArray
        // Directory-level events (no FileEvents flag) are enough to refresh the tree.
        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

/// Multi-root workspace shared by all windows, persisted in UserDefaults.
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()
    private static let defaultsKey = "workspaceRoots"

    @Published private(set) var roots: [FileNode] = []
    @Published var collapsed: Set<URL> = []
    @Published var hoveredRoot: URL? = nil

    private var watcher: WorkspaceWatcher?
    private var refreshWork: DispatchWorkItem?

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: WorkspaceStore.defaultsKey) ?? []
        var isDir: ObjCBool = false
        roots = paths
            .filter { FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue }
            .map { FileNode(url: URL(fileURLWithPath: $0)) }
        persist()
        startWatching()
    }

    private func persist() {
        UserDefaults.standard.set(roots.map { $0.url.path }, forKey: WorkspaceStore.defaultsKey)
    }

    private func startWatching() {
        if watcher == nil {
            watcher = WorkspaceWatcher { [weak self] changed in
                self?.handleFSEvents(changed)
            }
        }
        watcher?.setPaths(roots.map { $0.url.path })
    }

    private func handleFSEvents(_ changed: [String]) {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            var refreshed = Set<URL>()
            for path in changed {
                let url = URL(fileURLWithPath: path)
                for root in self.roots {
                    if url.path == root.url.path || url.path.hasPrefix(root.url.path + "/") {
                        if refreshed.insert(root.url).inserted {
                            self.refresh(root.url)
                        }
                    }
                }
            }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func add(_ urls: [URL]) {
        for url in urls where !roots.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            roots.append(FileNode(url: url))
        }
        persist()
        startWatching()
    }

    func remove(_ url: URL) {
        roots.removeAll { $0.url == url }
        collapsed.remove(url)
        persist()
        startWatching()
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
                Button {
                    ui.showFindInFiles = true
                } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help(t("findInFiles"))
                    .disabled(store.roots.isEmpty)
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

// MARK: - Find in Files

struct FindInFilesHit: Identifiable {
    let id = UUID()
    let url: URL
    let line: Int
    let snippet: String
}

final class FindInFilesModel: ObservableObject {
    @Published var query = ""
    @Published var results: [FindInFilesHit] = []
    @Published var isSearching = false
    @Published var status = ""
    private var workItem: DispatchWorkItem?

    func search() {
        workItem?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = []
            status = ""
            return
        }
        isSearching = true
        status = L10n.t("searching")
        let roots = WorkspaceStore.shared.roots.map { $0.url }
        let work = DispatchWorkItem { [weak self] in
            let hits = WorkspaceSearch.search(query: q, roots: roots)
            DispatchQueue.main.async {
                guard let self = self, !(self.workItem?.isCancelled ?? true) else { return }
                self.results = hits
                self.isSearching = false
                self.status = hits.isEmpty ? L10n.t("noResults") : L10n.f("resultsCount", L10n.currentPreference, hits.count)
            }
        }
        workItem = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }
}

enum WorkspaceSearch {
    static let textExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "json", "md", "txt", "csv", "tsv",
        "c", "h", "cpp", "hpp", "m", "mm", "go", "rs", "html", "htm", "css", "scss",
        "sh", "bash", "zsh", "xml", "plist", "yml", "yaml", "toml", "log", "text",
    ]

    static func search(query: String, roots: [URL], maxHits: Int = 200) -> [FindInFilesHit] {
        var hits: [FindInFilesHit] = []
        let fm = FileManager.default
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if hits.count >= maxHits { return hits }
                let name = url.lastPathComponent
                if FileNode.ignoredNames.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                let ext = url.pathExtension.lowercased()
                if !ext.isEmpty && !textExtensions.contains(ext) { continue }
                guard let data = try? Data(contentsOf: url), data.count < 2_000_000 else { continue }
                let (text, _) = TextDocument.decode(data, pathExtension: ext)
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (idx, line) in lines.enumerated() {
                    if hits.count >= maxHits { return hits }
                    if line.localizedCaseInsensitiveContains(query) {
                        let snippet = String(line).trimmingCharacters(in: .whitespaces)
                        let clipped = snippet.count > 160 ? String(snippet.prefix(160)) + "…" : snippet
                        hits.append(FindInFilesHit(url: url, line: idx + 1, snippet: clipped))
                    }
                }
            }
        }
        return hits
    }
}

struct FindInFilesSheet: View {
    @ObservedObject var ui: EditorUIState
    let theme: Theme
    @AppStorage("uiLanguage") private var uiLanguage: String = "system"
    @StateObject private var model = FindInFilesModel()

    private func t(_ key: String) -> String { L10n.t(key, uiLanguage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("findInFiles")).font(.headline)
            HStack {
                TextField(t("searchPlaceholder"), text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.search() }
                Button(t("search")) { model.search() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            List(model.results) { hit in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hit.url.lastPathComponent):\(hit.line)")
                        .font(.system(size: 12, weight: .semibold))
                    Text(hit.snippet)
                        .font(.system(size: 11).monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture { open(hit) }
            }
            .frame(minHeight: 280)
            HStack {
                Spacer()
                Button(t("cancel")) { ui.showFindInFiles = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }

    private func open(_ hit: FindInFilesHit) {
        ui.showFindInFiles = false
        NSDocumentController.shared.openDocument(withContentsOf: hit.url, display: true) { _, _, _ in }
    }
}
