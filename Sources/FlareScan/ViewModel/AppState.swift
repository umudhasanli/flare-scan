import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Central, main-actor-isolated state for the app: what was scanned, where the
/// user is focused, which visualization is showing, and scan progress.
@MainActor
final class AppState: ObservableObject {

    enum ViewMode: String, CaseIterable, Identifiable {
        case sunburst = "Sunburst"
        case treemap = "Treemap"
        case insights = "Insights"
        case memory = "Memory Watch"
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
    @Published var scanIssueCount = 0
    @Published var scanIssues: [ScanIssue] = []
    @Published var currentScanPath = ""
    @Published var scanRootURL: URL?
    @Published var pendingDeletion: FileNode?
    @Published var deletionError: String?
    @Published var insights: ScanInsights?
    /// `nil` means duplicate analysis has not run; an empty array means it ran cleanly.
    @Published var duplicateGroups: [DuplicateGroup]?
    @Published var isFindingDuplicates = false
    @Published var duplicateFilesHashed = 0
    @Published var duplicateCandidateFiles = 0
    @Published var duplicateError: String?
    @Published var isExportingReport = false
    @Published var exportError: String?
    @Published var lastExportURL: URL?
    @Published var hasSavedBaseline = false
    @Published var baselineSavedAt: Date?
    @Published var scanDelta: ScanDelta?
    @Published var isSavingBaseline = false
    @Published var historyError: String?
    @Published var memoryMonitorEnabled = false
    @Published var memoryMonitorInterval: MemoryMonitorInterval = .oneMinute
    @Published var isSamplingMemory = false
    @Published var memoryApps: [MemoryAppStat] = []
    @Published var memoryLastSampleAt: Date?
    @Published var memorySessionStartedAt: Date
    @Published var memoryTotalCurrentBytes: Int64 = 0
    @Published var memoryTotalPeakBytes: Int64 = 0
    @Published var memoryTotalAverageBytes: Int64 = 0
    @Published var memoryTotalPoints: [MemoryPoint] = []
    @Published var memorySampleCount = 0
    @Published var memoryAccessUnavailable = false
    @Published var pendingAppQuit: MemoryAppStat?
    @Published var memoryQuitError: String?

    private var scanTask: Task<Void, Never>?
    private var duplicateTask: Task<Void, Never>?
    private var memoryMonitorTask: Task<Void, Never>?
    private var currentSnapshot: ScanSnapshot?
    private var securityScopedURL: URL?
    private var memorySession: MemorySession
    private var memoryMonitorGeneration = 0
    /// Bumped on every scan/cancel so results from a superseded scan are ignored.
    private var scanGeneration = 0

    init() {
        let startedAt = Date()
        memorySessionStartedAt = startedAt
        memorySession = MemorySession(startedAt: startedAt)
        startMemoryMonitoring()
    }

    // MARK: - Scanning

    /// Presents an open panel and scans whatever folder or volume the user picks.
    func chooseAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder or volume to analyze"
        panel.prompt = "Scan"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(url)
    }

    func scan(_ url: URL) {
        stopScan()
        scanGeneration += 1
        let generation = scanGeneration

        // This also preserves compatibility with security-scoped URLs opened
        // by sandboxed development builds.
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        isScanning = true
        scannedFiles = 0
        scannedBytes = 0
        totalItems = 0
        scanIssueCount = 0
        scanIssues = []
        currentScanPath = "Starting…"
        scanRootURL = url
        root = nil
        focus = nil
        hovered = nil
        insights = nil
        duplicateGroups = nil
        duplicateError = nil
        exportError = nil
        lastExportURL = nil
        hasSavedBaseline = false
        baselineSavedAt = nil
        scanDelta = nil
        historyError = nil
        isSavingBaseline = false
        currentSnapshot = nil

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
            let issueCount = scanner.issueCount
            let issues = scanner.issues
            let cancelled = Task.isCancelled
            let analysis = cancelled ? nil : result.map { ScanInsights.build(from: $0) }
            let snapshot = cancelled ? nil : result.map { ScanSnapshot.capture(from: $0) }
            var delta: ScanDelta?
            var baselineDate: Date?
            var historyError: String?
            if let result, let snapshot, !cancelled {
                do {
                    if let baseline = try ScanSnapshotStore().load(for: url) {
                        baselineDate = baseline.createdAt
                        delta = ScanDelta.compare(
                            baseline: baseline,
                            current: snapshot,
                            root: result)
                    }
                } catch {
                    historyError = error.localizedDescription
                }
            }
            await self?.finishScan(
                generation: generation,
                result: cancelled ? nil : result,
                insights: analysis,
                count: count,
                issueCount: issueCount,
                issues: issues,
                snapshot: snapshot,
                delta: delta,
                baselineDate: baselineDate,
                historyError: historyError)
        }
    }

    func rescan() {
        if let url = scanRootURL { scan(url) }
    }

    func cancelScan() {
        stopScan()
        scanGeneration += 1
        isScanning = false
        isSavingBaseline = false
        currentScanPath = ""
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        duplicateTask?.cancel()
        duplicateTask = nil
        isFindingDuplicates = false
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

    private func finishScan(
        generation: Int,
        result: FileNode?,
        insights: ScanInsights?,
        count: Int,
        issueCount: Int,
        issues: [ScanIssue],
        snapshot: ScanSnapshot?,
        delta: ScanDelta?,
        baselineDate: Date?,
        historyError: String?
    ) {
        guard generation == scanGeneration else { return }
        if let result {
            root = result
            focus = result
            totalItems = count
            scanIssueCount = issueCount
            scanIssues = issues
            self.insights = insights
            currentSnapshot = snapshot
            scanDelta = delta
            baselineSavedAt = baselineDate
            hasSavedBaseline = baselineDate != nil
            self.historyError = historyError
        }
        isScanning = false
        currentScanPath = ""
    }

    // MARK: - Insights & duplicates

    var duplicateReclaimableBytes: Int64 {
        duplicateGroups?.reduce(0) { $0 + $1.reclaimableSize } ?? 0
    }

    func findDuplicates(minimumSize: Int64 = 1_048_576) {
        guard let root, !isScanning else { return }
        duplicateTask?.cancel()
        let generation = scanGeneration
        isFindingDuplicates = true
        duplicateGroups = nil
        duplicateFilesHashed = 0
        duplicateCandidateFiles = 0
        duplicateError = nil

        duplicateTask = Task.detached(priority: .userInitiated) { [weak self] in
            let groups = DuplicateFinder.find(
                in: root,
                minimumSize: minimumSize,
                shouldCancel: { Task.isCancelled },
                onProgress: { completed, total in
                    Task { @MainActor in
                        guard self?.scanGeneration == generation else { return }
                        self?.duplicateFilesHashed = completed
                        self?.duplicateCandidateFiles = total
                    }
                })
            let cancelled = Task.isCancelled
            await self?.finishDuplicateScan(
                generation: generation,
                groups: cancelled ? nil : groups,
                cancelled: cancelled)
        }
    }

    func cancelDuplicateScan() {
        duplicateTask?.cancel()
        duplicateTask = nil
        isFindingDuplicates = false
    }

    private func finishDuplicateScan(
        generation: Int,
        groups: [DuplicateGroup]?,
        cancelled: Bool
    ) {
        guard generation == scanGeneration else { return }
        isFindingDuplicates = false
        duplicateTask = nil
        if !cancelled { duplicateGroups = groups ?? [] }
    }

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func saveCurrentScanAsBaseline() {
        guard let snapshot = currentSnapshot,
              let rootURL = scanRootURL,
              !isSavingBaseline else { return }
        let generation = scanGeneration
        isSavingBaseline = true
        historyError = nil
        Task.detached(priority: .utility) { [weak self] in
            do {
                try ScanSnapshotStore().save(snapshot, for: rootURL)
                await self?.finishBaselineChange(
                    generation: generation,
                    saved: snapshot,
                    error: nil)
            } catch {
                await self?.finishBaselineChange(
                    generation: generation,
                    saved: nil,
                    error: error.localizedDescription)
            }
        }
    }

    func forgetSavedBaseline() {
        guard let rootURL = scanRootURL, !isSavingBaseline else { return }
        let generation = scanGeneration
        isSavingBaseline = true
        historyError = nil
        Task.detached(priority: .utility) { [weak self] in
            do {
                try ScanSnapshotStore().remove(for: rootURL)
                await self?.finishBaselineChange(
                    generation: generation,
                    saved: nil,
                    error: nil)
            } catch {
                await self?.finishBaselineChange(
                    generation: generation,
                    saved: nil,
                    error: error.localizedDescription)
            }
        }
    }

    private func finishBaselineChange(
        generation: Int,
        saved: ScanSnapshot?,
        error: String?
    ) {
        guard generation == scanGeneration else { return }
        isSavingBaseline = false
        historyError = error
        guard error == nil else { return }
        hasSavedBaseline = saved != nil
        baselineSavedAt = saved?.createdAt
        scanDelta = nil
    }

    // MARK: - Memory Watch

    func startMemoryMonitoring() {
        guard memoryMonitorTask == nil else {
            memoryMonitorEnabled = true
            return
        }
        memoryMonitorEnabled = true
        memoryMonitorGeneration += 1
        let generation = memoryMonitorGeneration
        let interval = memoryMonitorInterval.rawValue
        memoryMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.collectMemorySample(generation: generation)
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    func stopMemoryMonitoring() {
        memoryMonitorGeneration += 1
        memoryMonitorTask?.cancel()
        memoryMonitorTask = nil
        memorySession.breakSamplingContinuity()
        memoryMonitorEnabled = false
        isSamplingMemory = false
    }

    func setMemoryMonitorInterval(_ interval: MemoryMonitorInterval) {
        guard memoryMonitorInterval != interval else { return }
        let wasEnabled = memoryMonitorEnabled
        stopMemoryMonitoring()
        memoryMonitorInterval = interval
        if wasEnabled { startMemoryMonitoring() }
    }

    func refreshMemoryNow() {
        if !memoryMonitorEnabled {
            startMemoryMonitoring()
            return
        }
        let generation = memoryMonitorGeneration
        Task { [weak self] in
            await self?.collectMemorySample(generation: generation)
        }
    }

    func resetMemorySession() {
        let startedAt = Date()
        memorySession = MemorySession(startedAt: startedAt)
        memorySessionStartedAt = startedAt
        memoryApps = []
        memoryLastSampleAt = nil
        memoryTotalCurrentBytes = 0
        memoryTotalPeakBytes = 0
        memoryTotalAverageBytes = 0
        memoryTotalPoints = []
        memorySampleCount = 0
        memoryAccessUnavailable = false
        if memoryMonitorEnabled { refreshMemoryNow() }
    }

    func requestQuit(_ stat: MemoryAppStat) {
        guard stat.canRequestQuit else { return }
        pendingAppQuit = stat
    }

    func cancelAppQuit() {
        pendingAppQuit = nil
    }

    func confirmAppQuit() {
        guard let stat = pendingAppQuit else { return }
        pendingAppQuit = nil
        var sent = false
        for pid in stat.processIdentifiers {
            guard pid != ProcessInfo.processInfo.processIdentifier,
                  let application = NSRunningApplication(processIdentifier: pid),
                  !application.isTerminated else { continue }
            sent = application.terminate() || sent
        }
        guard sent else {
            memoryQuitError = "The normal quit request could not be sent. The app may have already closed."
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.refreshMemoryNow()
        }
    }

    private func collectMemorySample(generation: Int) async {
        guard generation == memoryMonitorGeneration,
              memoryMonitorEnabled,
              !isSamplingMemory else { return }
        isSamplingMemory = true
        let readings = await Task.detached(priority: .utility) {
            MemorySampler.sample()
        }.value
        guard generation == memoryMonitorGeneration, memoryMonitorEnabled else {
            return
        }
        let date = Date()
        memoryAccessUnavailable = !readings.isEmpty
            && readings.allSatisfy { $0.residentBytes == 0 }
        memorySession.ingest(readings, at: date)
        applyMemorySnapshot(memorySession.snapshot(referenceDate: date))
        isSamplingMemory = false
    }

    private func applyMemorySnapshot(_ snapshot: MemorySessionSnapshot) {
        memorySessionStartedAt = snapshot.startedAt
        memoryLastSampleAt = snapshot.lastSampleAt
        memorySampleCount = snapshot.sampleCount
        memoryTotalCurrentBytes = snapshot.totalCurrentBytes
        memoryTotalPeakBytes = snapshot.totalPeakBytes
        memoryTotalAverageBytes = snapshot.totalAverageBytes
        memoryTotalPoints = snapshot.totalPoints
        memoryApps = snapshot.apps
    }

    func exportInsights(as format: InsightReportFormat) {
        guard let root, let insights, !isExportingReport else { return }

        let panel = NSSavePanel()
        panel.title = "Save Flare Scan Report"
        panel.prompt = "Save"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format == .json ? .json : .commaSeparatedText]
        let date = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Flare Scan Report \(date).\(format.filenameExtension)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let report = InsightReport(
            root: root,
            insights: insights,
            duplicateGroups: duplicateGroups ?? [],
            scanIssueCount: scanIssueCount,
            scanIssues: scanIssues,
            scanDelta: scanDelta)
        isExportingReport = true
        exportError = nil
        lastExportURL = nil

        Task.detached(priority: .utility) { [weak self] in
            do {
                let data = try report.data(format: format)
                try data.write(to: destination, options: .atomic)
                await self?.finishReportExport(destination: destination, error: nil)
            } catch {
                await self?.finishReportExport(
                    destination: nil,
                    error: error.localizedDescription)
            }
        }
    }

    func revealLastExport() {
        guard let lastExportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastExportURL])
    }

    private func finishReportExport(destination: URL?, error: String?) {
        isExportingReport = false
        lastExportURL = destination
        exportError = error
    }

    private func rebuildInsights() {
        guard let root else { insights = nil; return }
        let generation = scanGeneration
        Task.detached(priority: .utility) { [weak self] in
            let updated = ScanInsights.build(from: root)
            await self?.applyRebuiltInsights(updated, generation: generation)
        }
    }

    private func applyRebuiltInsights(_ updated: ScanInsights, generation: Int) {
        guard scanGeneration == generation else { return }
        insights = updated
    }

    private func refreshHistoryAfterTreeMutation() {
        guard let root, let rootURL = scanRootURL else { return }
        let generation = scanGeneration
        currentSnapshot = nil
        scanDelta = nil
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = ScanSnapshot.capture(from: root)
            do {
                let baseline = try ScanSnapshotStore().load(for: rootURL)
                let delta = baseline.map {
                    ScanDelta.compare(baseline: $0, current: snapshot, root: root)
                }
                await self?.applyRefreshedHistory(
                    generation: generation,
                    snapshot: snapshot,
                    delta: delta,
                    baselineDate: baseline?.createdAt,
                    error: nil)
            } catch {
                await self?.applyRefreshedHistory(
                    generation: generation,
                    snapshot: snapshot,
                    delta: nil,
                    baselineDate: nil,
                    error: error.localizedDescription)
            }
        }
    }

    private func applyRefreshedHistory(
        generation: Int,
        snapshot: ScanSnapshot,
        delta: ScanDelta?,
        baselineDate: Date?,
        error: String?
    ) {
        guard generation == scanGeneration else { return }
        currentSnapshot = snapshot
        scanDelta = delta
        baselineSavedAt = baselineDate
        hasSavedBaseline = baselineDate != nil
        historyError = error
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
            deletionError = "The selected scan root is protected and cannot be removed."
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
            current.logicalSize = max(0, current.logicalSize - node.logicalSize)
            ancestor = current.parent
        }
        totalItems = max(0, totalItems - itemCount(in: node))
        duplicateTask?.cancel()
        duplicateTask = nil
        isFindingDuplicates = false
        duplicateGroups = nil
        rebuildInsights()
        refreshHistoryAfterTreeMutation()
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
        case .noActiveScan: return "No active scan was found; nothing was removed."
        case .protectedRoot: return "The selected scan root cannot be removed."
        case .outsideSelection: return "The item is outside the selected scan root; nothing was removed."
        case .missingItem: return "The item no longer exists on disk."
        }
    }
}
