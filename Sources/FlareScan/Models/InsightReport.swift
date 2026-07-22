import Foundation

enum InsightReportFormat: String, Sendable {
    case json, csv

    var filenameExtension: String { rawValue }
}

struct InsightReport: Codable, Sendable {
    struct Summary: Codable, Sendable {
        let allocatedBytes: Int64
        let logicalBytes: Int64
        let fileCount: Int
        let directoryCount: Int
        let duplicateGroups: Int
        let duplicateReclaimableBytes: Int64
        let unreadableItems: Int
    }

    struct Category: Codable, Sendable {
        let id: String
        let title: String
        let allocatedBytes: Int64
        let fileCount: Int
    }

    struct File: Codable, Sendable {
        let name: String
        let path: String
        let allocatedBytes: Int64
        let logicalBytes: Int64
        let modifiedAt: Date?
        let category: String
    }

    struct Duplicate: Codable, Sendable {
        let logicalBytesPerFile: Int64
        let reclaimableBytes: Int64
        let files: [File]
    }

    struct Issue: Codable, Sendable {
        let path: String
        let message: String
    }

    struct HistoryChange: Codable, Sendable {
        let path: String
        let kind: String
        let previousBytes: Int64
        let currentBytes: Int64
        let deltaBytes: Int64
    }

    struct History: Codable, Sendable {
        let baselineAt: Date
        let netAllocatedChange: Int64
        let addedBytes: Int64
        let grownBytes: Int64
        let releasedBytes: Int64
        let wasTruncated: Bool
        let changes: [HistoryChange]
    }

    let schemaVersion: Int
    let generatedAt: Date
    let rootName: String
    let rootPath: String
    let summary: Summary
    let categories: [Category]
    let largestFiles: [File]
    let oldLargeFiles: [File]
    let duplicates: [Duplicate]
    /// Bounded sample; the full count is available in `summary.unreadableItems`.
    let scanIssues: [Issue]
    let history: History?

    init(
        root: FileNode,
        insights: ScanInsights,
        duplicateGroups: [DuplicateGroup],
        scanIssueCount: Int = 0,
        scanIssues: [ScanIssue] = [],
        scanDelta: ScanDelta? = nil,
        generatedAt: Date = Date()
    ) {
        schemaVersion = 1
        self.generatedAt = generatedAt
        rootName = root.displayName
        rootPath = root.url.path
        summary = Summary(
            allocatedBytes: root.size,
            logicalBytes: root.logicalSize,
            fileCount: insights.fileCount,
            directoryCount: insights.directoryCount,
            duplicateGroups: duplicateGroups.count,
            duplicateReclaimableBytes: duplicateGroups.reduce(0) { $0 + $1.reclaimableSize },
            unreadableItems: scanIssueCount)
        categories = insights.categories.map {
            Category(
                id: $0.category.id,
                title: $0.category.title,
                allocatedBytes: $0.bytes,
                fileCount: $0.fileCount)
        }
        largestFiles = insights.largestFiles.map(Self.file)
        oldLargeFiles = insights.oldLargeFiles.map(Self.file)
        duplicates = duplicateGroups.map { group in
            Duplicate(
                logicalBytesPerFile: group.logicalSize,
                reclaimableBytes: group.reclaimableSize,
                files: group.files.map(Self.file))
        }
        self.scanIssues = scanIssues.map { Issue(path: $0.path, message: $0.message) }
        history = scanDelta.map { delta in
            History(
                baselineAt: delta.baselineDate,
                netAllocatedChange: delta.netAllocatedChange,
                addedBytes: delta.addedBytes,
                grownBytes: delta.grownBytes,
                releasedBytes: delta.releasedBytes,
                wasTruncated: delta.baselineWasTruncated || delta.currentWasTruncated,
                changes: delta.changes.map {
                    HistoryChange(
                        path: $0.relativePath,
                        kind: $0.kind.rawValue,
                        previousBytes: $0.previousSize,
                        currentBytes: $0.currentSize,
                        deltaBytes: $0.delta)
                })
        }
    }

    func data(format: InsightReportFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(self)
        case .csv:
            return Data(csv.utf8)
        }
    }

    private var csv: String {
        struct Row {
            let file: File
            var findings: Set<String>
            var duplicateGroup: Int?
        }

        var rows: [String: Row] = [:]
        func add(_ file: File, finding: String, duplicateGroup: Int? = nil) {
            if var existing = rows[file.path] {
                existing.findings.insert(finding)
                if let duplicateGroup { existing.duplicateGroup = duplicateGroup }
                rows[file.path] = existing
            } else {
                rows[file.path] = Row(
                    file: file,
                    findings: [finding],
                    duplicateGroup: duplicateGroup)
            }
        }

        for file in largestFiles { add(file, finding: "largest") }
        for file in oldLargeFiles { add(file, finding: "old_large") }
        for (index, group) in duplicates.enumerated() {
            for file in group.files {
                add(file, finding: "duplicate", duplicateGroup: index + 1)
            }
        }
        if let history {
            for change in history.changes {
                let absolutePath = URL(fileURLWithPath: rootPath)
                    .appendingPathComponent(change.path).path
                add(
                    File(
                        name: URL(fileURLWithPath: change.path).lastPathComponent,
                        path: absolutePath,
                        allocatedBytes: change.currentBytes,
                        logicalBytes: change.currentBytes,
                        modifiedAt: nil,
                        category: FileCategory.classify(URL(fileURLWithPath: change.path)).id),
                    finding: "history_\(change.kind)")
            }
        }

        let formatter = ISO8601DateFormatter()
        let header = "findings,name,path,allocated_bytes,logical_bytes,modified_at,category,duplicate_group"
        let body = rows.values.sorted { lhs, rhs in
            if lhs.file.allocatedBytes == rhs.file.allocatedBytes {
                return lhs.file.path < rhs.file.path
            }
            return lhs.file.allocatedBytes > rhs.file.allocatedBytes
        }.map { row in
            [
                row.findings.sorted().joined(separator: "+"),
                row.file.name,
                row.file.path,
                String(row.file.allocatedBytes),
                String(row.file.logicalBytes),
                row.file.modifiedAt.map(formatter.string) ?? "",
                row.file.category,
                row.duplicateGroup.map(String.init) ?? ""
            ].map(Self.escapeCSV).joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n") + "\n"
    }

    private static func file(_ node: FileNode) -> File {
        File(
            name: node.displayName,
            path: node.url.path,
            allocatedBytes: node.size,
            logicalBytes: node.logicalSize,
            modifiedAt: node.modifiedAt,
            category: FileCategory.classify(node.url).id)
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
