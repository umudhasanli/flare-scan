import Foundation

/// Recursively walks a directory tree and builds a `FileNode` hierarchy.
///
/// Designed to run synchronously inside a background task. It never writes to
/// disk and swallows permission errors (`try?`), so a locked-down folder simply
/// contributes nothing instead of aborting the whole scan.
final class Scanner {

    /// Called (throttled) with `(filesScanned, bytesScanned, lastVisitedPath)`.
    var onProgress: ((Int, Int64, String) -> Void)?

    /// Return `true` to abort the scan cooperatively.
    var shouldCancel: () -> Bool = { false }

    /// Total number of file-system items visited so far.
    private(set) var fileCount = 0
    /// Total read failures; `issues` keeps a bounded sample for the UI/report.
    private(set) var issueCount = 0
    private(set) var issues: [ScanIssue] = []

    private var bytesScanned: Int64 = 0
    private var lastReported = 0

    private let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey, .nameKey
    ]
    private lazy var keySet = Set(keys)

    /// Scans `url` and returns the built tree, or `nil` if cancelled at the root.
    func scan(_ url: URL) -> FileNode? {
        if shouldCancel() { return nil }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: keySet)
        } catch {
            recordIssue(url, error: error)
            return nil
        }
        let name = values.name ?? url.lastPathComponent
        let isSymlink = values.isSymbolicLink ?? false
        // Never follow symlinks: it avoids infinite loops and double-counting.
        let isDirectory = (values.isDirectory ?? false) && !isSymlink

        if isDirectory {
            let node = FileNode(
                name: name,
                url: url,
                isDirectory: true,
                size: 0,
                logicalSize: 0,
                modifiedAt: values.contentModificationDate)
            let contents: [URL]
            do {
                contents = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [])
            } catch {
                recordIssue(url, error: error)
                contents = []
            }

            var total: Int64 = 0
            var logicalTotal: Int64 = 0
            var children: [FileNode] = []
            children.reserveCapacity(contents.count)

            for child in contents {
                if shouldCancel() { break }
                if let childNode = scan(child) {
                    childNode.parent = node
                    total += childNode.size
                    logicalTotal += childNode.logicalSize
                    children.append(childNode)
                }
            }

            children.sort { $0.size > $1.size }
            node.children = children
            node.size = total
            node.logicalSize = logicalTotal
            fileCount += 1
            report(name)
            return node
        } else {
            let size = leafSize(values)
            let logicalSize = Int64(values.fileSize ?? Int(size))
            fileCount += 1
            bytesScanned += size
            report(name)
            return FileNode(name: name, url: url, isDirectory: false,
                            size: size, logicalSize: logicalSize,
                            modifiedAt: values.contentModificationDate)
        }
    }

    /// Prefer the true on-disk (allocated) size, matching what tools like
    /// DaisyDisk report; fall back to logical size when unavailable.
    private func leafSize(_ values: URLResourceValues) -> Int64 {
        if let s = values.totalFileAllocatedSize { return Int64(s) }
        if let s = values.fileAllocatedSize { return Int64(s) }
        if let s = values.fileSize { return Int64(s) }
        return 0
    }

    private func recordIssue(_ url: URL, error: Error) {
        issueCount += 1
        if issues.count < 100 {
            issues.append(ScanIssue(path: url.path, message: error.localizedDescription))
        }
    }

    private func report(_ path: String) {
        if fileCount - lastReported >= 400 {
            lastReported = fileCount
            onProgress?(fileCount, bytesScanned, path)
        }
    }
}
