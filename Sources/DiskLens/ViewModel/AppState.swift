import SwiftUI
import AppKit

/// Central, main-actor-isolated state for the app: what was scanned, where the
/// user is focused, which visualization is showing, and scan progress.
@MainActor
final class AppState: ObservableObject {

    enum ViewMode: String, CaseIterable, Identifiable {
        case sunburst = "Sunburst"
        case treemap = "Treemap"
        var id: String { rawValue }
    }

    /// The full scanned tree.
    @Published var root: FileNode?
    /// The node currently at the center (the zoom target).
    @Published var focus: FileNode?
    /// The node under the cursor, for the status bar and highlights.
    @Published var hovered: FileNode?
    @Published var mode: ViewMode = .sunburst

    @Published var isScanning = false
    @Published var scannedFiles = 0
    @Published var scannedBytes: Int64 = 0
    @Published var totalItems = 0
    @Published var currentScanPath = ""
    @Published var scanRootURL: URL?
    @Published var pendingDeletion: FileNode?
    @Published var deletionError: String?

    private var scanTask: Task<Void, Never>?
    private var securityScopedURL: URL?
    /// Bumped on every scan/cancel so results from a superseded scan are ignored.
    private var scanGeneration = 0

    // MARK: - Scanning

    /// Presents an open panel and scans whatever folder or volume the user picks.
    func chooseAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Analiz üçün qovluq və ya disk seçin"
        panel.prompt = "Tara"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(url)
    }

    func scan(_ url: URL) {
        stopScan()
        scanGeneration += 1
        let generation = scanGeneration

        // Under the sandbox, an open-panel selection grants access for this
        // launch; this call also covers the case of a re-resolved URL.
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        isScanning = true
        scannedFiles = 0
        scannedBytes = 0
        totalItems = 0
        currentScanPath = "Başlanır…"
        scanRootURL = url
        root = nil
        focus = nil
        hovered = nil

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scanner = Scanner()
            scanner.shouldCancel = { Task.isCancelled }
            scanner.onProgress = { files, bytes, path in
                Task { @MainActor in
                    self?.applyProgress(generation: generation, files: files, bytes: bytes, path: path)
                }
            }

            let result = scanner.scan(url)
            let count = scanner.fileCount
            let cancelled = Task.isCancelled
            await self?.finishScan(generation: generation, result: cancelled ? nil : result, count: count)
        }
    }

    func rescan() {
        if let url = scanRootURL { scan(url) }
    }

    func cancelScan() {
        stopScan()
        scanGeneration += 1
        isScanning = false
        currentScanPath = ""
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopedURL = nil
    }

    private func applyProgress(generation: Int, files: Int, bytes: Int64, path: String) {
        guard generation == scanGeneration else { return }
        scannedFiles = files
        scannedBytes = bytes
        currentScanPath = path
    }

    private func finishScan(generation: Int, result: FileNode?, count: Int) {
        guard generation == scanGeneration else { return }
        if let result {
            root = result
            focus = result
            totalItems = count
        }
        isScanning = false
        currentScanPath = ""
    }

    // MARK: - Navigation

    func drill(into node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        focus = node
        hovered = nil
    }

    func goUp() {
        if let parent = focus?.parent {
            focus = parent
            hovered = nil
        }
    }

    func setFocus(_ node: FileNode) {
        focus = node
        hovered = nil
    }

    // MARK: - Safe deletion

    /// Starts the explicit confirmation flow. The scan root itself is never a
    /// valid deletion target.
    func requestDeletion(of node: FileNode) {
        guard node.id != root?.id else {
            deletionError = "Seçilmiş əsas qovluq təhlükəsizlik səbəbilə silinə bilməz."
            return
        }
        pendingDeletion = node
    }

    func cancelDeletion() {
        pendingDeletion = nil
    }

    /// Moves the confirmed item to macOS Trash. Before touching disk, verify
    /// both tree membership and path containment to prevent stale or forged
    /// nodes from escaping the user-selected scan root.
    func confirmDeletion() {
        guard let node = pendingDeletion else { return }
        pendingDeletion = nil

        do {
            try validateDeletionTarget(node)
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            removeFromScannedTree(node)
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func validateDeletionTarget(_ node: FileNode) throws {
        guard let root, let selectedRoot = scanRootURL else {
            throw DeletionSafetyError.noActiveScan
        }
        guard node.id != root.id, node.parent != nil else {
            throw DeletionSafetyError.protectedRoot
        }

        var cursor: FileNode? = node
        var belongsToTree = false
        while let current = cursor {
            if current.id == root.id { belongsToTree = true; break }
            cursor = current.parent
        }
        guard belongsToTree else { throw DeletionSafetyError.outsideSelection }

        let rootPath = selectedRoot.standardizedFileURL.path
        let targetPath = node.url.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard targetPath != rootPath, targetPath.hasPrefix(prefix) else {
            throw DeletionSafetyError.outsideSelection
        }
        guard FileManager.default.fileExists(atPath: targetPath) else {
            throw DeletionSafetyError.missingItem
        }
    }

    private func removeFromScannedTree(_ node: FileNode) {
        guard let parent = node.parent else { return }
        parent.children.removeAll { $0.id == node.id }

        var ancestor: FileNode? = parent
        while let current = ancestor {
            current.size = max(0, current.size - node.size)
            ancestor = current.parent
        }
        totalItems = max(0, totalItems - itemCount(in: node))
        hovered = nil
        objectWillChange.send()
    }

    private func itemCount(in node: FileNode) -> Int {
        1 + node.children.reduce(0) { $0 + itemCount(in: $1) }
    }
}

private enum DeletionSafetyError: LocalizedError {
    case noActiveScan, protectedRoot, outsideSelection, missingItem

    var errorDescription: String? {
        switch self {
        case .noActiveScan: return "Aktiv tarama tapılmadı; heç nə silinmədi."
        case .protectedRoot: return "Əsas seçilmiş qovluq silinə bilməz."
        case .outsideSelection: return "Element seçilmiş qovluğun xaricindədir; heç nə silinmədi."
        case .missingItem: return "Element artıq diskdə mövcud deyil."
        }
    }
}
