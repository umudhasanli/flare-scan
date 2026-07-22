import Foundation
import Testing
@testable import FlareScan

@Suite("Scan history")
struct ScanHistoryTests {
    @Test("compares added, grown, shrunk, and removed files")
    func comparesSnapshots() {
        let rootURL = URL(fileURLWithPath: "/tmp/history-root")
        let root = FileNode(
            name: "history-root",
            url: rootURL,
            isDirectory: true,
            size: 800,
            logicalSize: 800)
        root.children = [
            file("grown.bin", size: 150, root: root),
            file("added.bin", size: 400, root: root),
            file("shrunk.bin", size: 250, root: root)
        ]
        let baseline = ScanSnapshot(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            rootAllocatedSize: 600,
            rootLogicalSize: 600,
            minimumTrackedSize: 1,
            totalEligibleFiles: 3,
            isTruncated: false,
            entries: [
                .init(relativePath: "grown.bin", allocatedSize: 100, logicalSize: 100),
                .init(relativePath: "removed.bin", allocatedSize: 200, logicalSize: 200),
                .init(relativePath: "shrunk.bin", allocatedSize: 300, logicalSize: 300)
            ])
        let current = ScanSnapshot.capture(from: root, minimumTrackedSize: 1)

        let delta = ScanDelta.compare(baseline: baseline, current: current, root: root)
        let kinds = Dictionary(uniqueKeysWithValues: delta.changes.map {
            ($0.relativePath, $0.kind)
        })

        #expect(kinds["added.bin"] == .added)
        #expect(kinds["grown.bin"] == .grown)
        #expect(kinds["shrunk.bin"] == .shrunk)
        #expect(kinds["removed.bin"] == .removed)
        #expect(delta.addedBytes == 400)
        #expect(delta.grownBytes == 50)
        #expect(delta.releasedBytes == 250)
        #expect(delta.netAllocatedChange == 200)
        #expect(delta.changes.first { $0.relativePath == "added.bin" }?.node != nil)
        #expect(delta.changes.first { $0.relativePath == "removed.bin" }?.node == nil)
    }

    @Test("stores a snapshot under a hashed root identity and can forget it")
    func persistsSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flare-scan-history-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScanSnapshotStore(directory: directory)
        let rootURL = URL(fileURLWithPath: "/Users/example/Private Folder")
        let snapshot = ScanSnapshot(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootAllocatedSize: 42,
            rootLogicalSize: 40,
            minimumTrackedSize: 1,
            totalEligibleFiles: 1,
            isTruncated: false,
            entries: [.init(relativePath: "file.bin", allocatedSize: 42, logicalSize: 40)])

        try store.save(snapshot, for: rootURL)
        let loadedSnapshot = try store.load(for: rootURL)
        let loaded = try #require(loadedSnapshot)
        #expect(loaded.rootAllocatedSize == 42)
        #expect(loaded.entries.first?.relativePath == "file.bin")

        try store.remove(for: rootURL)
        #expect(try store.load(for: rootURL) == nil)
    }

    @Test("does not invent additions or removals from capped snapshots")
    func handlesTruncationConservatively() {
        let rootURL = URL(fileURLWithPath: "/tmp/truncated-history-root")
        let root = FileNode(
            name: "truncated-history-root",
            url: rootURL,
            isDirectory: true,
            size: 900,
            logicalSize: 900)
        root.children = [file("current-only.bin", size: 900, root: root)]
        let baseline = ScanSnapshot(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            rootAllocatedSize: 800,
            rootLogicalSize: 800,
            minimumTrackedSize: 1,
            totalEligibleFiles: 2,
            isTruncated: true,
            entries: [.init(relativePath: "old-only.bin", allocatedSize: 800, logicalSize: 800)])
        let current = ScanSnapshot(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootAllocatedSize: 900,
            rootLogicalSize: 900,
            minimumTrackedSize: 1,
            totalEligibleFiles: 2,
            isTruncated: true,
            entries: [
                .init(relativePath: "current-only.bin", allocatedSize: 900, logicalSize: 900)
            ])

        let delta = ScanDelta.compare(baseline: baseline, current: current, root: root)

        #expect(delta.changes.isEmpty)
        #expect(delta.addedBytes == 0)
        #expect(delta.releasedBytes == 0)
        #expect(delta.netAllocatedChange == 100)
    }

    private func file(_ name: String, size: Int64, root: FileNode) -> FileNode {
        FileNode(
            name: name,
            url: root.url.appendingPathComponent(name),
            isDirectory: false,
            size: size,
            logicalSize: size,
            parent: root)
    }
}
