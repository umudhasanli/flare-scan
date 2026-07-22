import CryptoKit
import Foundation

struct ScanSnapshot: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let relativePath: String
        let allocatedSize: Int64
        let logicalSize: Int64
    }

    let schemaVersion: Int
    let createdAt: Date
    let rootAllocatedSize: Int64
    let rootLogicalSize: Int64
    let minimumTrackedSize: Int64
    let totalEligibleFiles: Int
    let isTruncated: Bool
    let entries: [Entry]

    static func capture(
        from root: FileNode,
        minimumTrackedSize: Int64 = 1_048_576,
        maximumEntries: Int = 50_000,
        createdAt: Date = Date()
    ) -> ScanSnapshot {
        var entries: [Entry] = []
        var totalEligibleFiles = 0
        var stack = [root]
        let rootPath = root.url.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"

        while let node = stack.popLast() {
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else if node.size >= minimumTrackedSize {
                totalEligibleFiles += 1
                let path = node.url.standardizedFileURL.path
                guard path.hasPrefix(prefix) else { continue }
                entries.append(Entry(
                    relativePath: String(path.dropFirst(prefix.count)),
                    allocatedSize: node.size,
                    logicalSize: node.logicalSize))
            }
        }

        entries.sort { lhs, rhs in
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.relativePath < rhs.relativePath
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        let entryLimit = max(0, maximumEntries)
        let truncated = entries.count > entryLimit
        if truncated { entries.removeLast(entries.count - entryLimit) }
        entries.sort { $0.relativePath < $1.relativePath }

        return ScanSnapshot(
            schemaVersion: 1,
            createdAt: createdAt,
            rootAllocatedSize: root.size,
            rootLogicalSize: root.logicalSize,
            minimumTrackedSize: minimumTrackedSize,
            totalEligibleFiles: totalEligibleFiles,
            isTruncated: truncated,
            entries: entries)
    }
}

enum StorageChangeKind: String, Sendable {
    case added, grown, shrunk, removed

    var title: String {
        switch self {
        case .added: return "Added"
        case .grown: return "Grew"
        case .shrunk: return "Shrank"
        case .removed: return "Removed or moved"
        }
    }
}

struct StorageChange: Identifiable, @unchecked Sendable {
    let relativePath: String
    let previousSize: Int64
    let currentSize: Int64
    let kind: StorageChangeKind
    let node: FileNode?

    var id: String { relativePath }
    var delta: Int64 { currentSize - previousSize }
}

struct ScanDelta: @unchecked Sendable {
    let baselineDate: Date
    let netAllocatedChange: Int64
    let addedBytes: Int64
    let grownBytes: Int64
    let releasedBytes: Int64
    let baselineWasTruncated: Bool
    let currentWasTruncated: Bool
    let changes: [StorageChange]

    static func compare(
        baseline: ScanSnapshot,
        current: ScanSnapshot,
        root: FileNode,
        maximumChanges: Int = 100
    ) -> ScanDelta {
        let previous = Dictionary(uniqueKeysWithValues: baseline.entries.map {
            ($0.relativePath, $0)
        })
        let now = Dictionary(uniqueKeysWithValues: current.entries.map {
            ($0.relativePath, $0)
        })
        let nodes = nodesByRelativePath(root: root, minimumSize: current.minimumTrackedSize)
        let paths = Set(previous.keys).union(now.keys)
        var changes: [StorageChange] = []
        var addedBytes: Int64 = 0
        var grownBytes: Int64 = 0
        var releasedBytes: Int64 = 0

        for path in paths {
            let oldSize = previous[path]?.allocatedSize ?? 0
            let newSize = now[path]?.allocatedSize ?? 0
            guard oldSize != newSize else { continue }

            let kind: StorageChangeKind
            if previous[path] == nil {
                // A truncated baseline cannot prove that this path is new; it
                // may simply have fallen below the old top-N cutoff.
                guard !baseline.isTruncated else { continue }
                kind = .added
                addedBytes += newSize
            } else if now[path] == nil {
                // Likewise, absence from a truncated current snapshot does not
                // prove removal.
                guard !current.isTruncated else { continue }
                kind = .removed
                releasedBytes += oldSize
            } else if newSize > oldSize {
                kind = .grown
                grownBytes += newSize - oldSize
            } else {
                kind = .shrunk
                releasedBytes += oldSize - newSize
            }
            changes.append(StorageChange(
                relativePath: path,
                previousSize: oldSize,
                currentSize: newSize,
                kind: kind,
                node: nodes[path]))
        }

        changes.sort { lhs, rhs in
            let left = abs(lhs.delta)
            let right = abs(rhs.delta)
            if left == right { return lhs.relativePath < rhs.relativePath }
            return left > right
        }
        let changeLimit = max(0, maximumChanges)
        if changes.count > changeLimit {
            changes.removeLast(changes.count - changeLimit)
        }

        return ScanDelta(
            baselineDate: baseline.createdAt,
            netAllocatedChange: current.rootAllocatedSize - baseline.rootAllocatedSize,
            addedBytes: addedBytes,
            grownBytes: grownBytes,
            releasedBytes: releasedBytes,
            baselineWasTruncated: baseline.isTruncated,
            currentWasTruncated: current.isTruncated,
            changes: changes)
    }

    private static func nodesByRelativePath(
        root: FileNode,
        minimumSize: Int64
    ) -> [String: FileNode] {
        var nodes: [String: FileNode] = [:]
        var stack = [root]
        let rootPath = root.url.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        while let node = stack.popLast() {
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else if node.size >= minimumSize {
                let path = node.url.standardizedFileURL.path
                if path.hasPrefix(prefix) {
                    nodes[String(path.dropFirst(prefix.count))] = node
                }
            }
        }
        return nodes
    }
}

struct ScanSnapshotStore: Sendable {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.directory = base
                .appendingPathComponent("Flare Scan", isDirectory: true)
                .appendingPathComponent("Snapshots", isDirectory: true)
        }
    }

    func load(for rootURL: URL) throws -> ScanSnapshot? {
        let url = snapshotURL(for: rootURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanSnapshot.self, from: Data(contentsOf: url))
    }

    func save(_ snapshot: ScanSnapshot, for rootURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: snapshotURL(for: rootURL), options: .atomic)
    }

    func remove(for rootURL: URL) throws {
        let url = snapshotURL(for: rootURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func snapshotURL(for rootURL: URL) -> URL {
        let path = rootURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("\(digest).json")
    }
}
