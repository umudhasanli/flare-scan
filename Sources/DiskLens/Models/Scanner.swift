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

    private var bytesScanned: Int64 = 0
    private var lastReported = 0

    private let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .nameKey
    ]
    private lazy var keySet = Set(keys)

    /// Scans `url` and returns the built tree, or `nil` if cancelled at the root.
    func scan(_ url: URL) -> FileNode? {
        if shouldCancel() { return nil }

        let values = try? url.resourceValues(forKeys: keySet)
        let name = values?.name ?? url.lastPathComponent
        let isSymlink = values?.isSymbolicLink ?? false
        // Never follow symlinks: it avoids infinite loops and double-counting.
        let isDirectory = (values?.isDirectory ?? false) && !isSymlink

        if isDirectory {
            let node = FileNode(name: name, url: url, isDirectory: true, size: 0)
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [])) ?? []

            var total: Int64 = 0
            var children: [FileNode] = []
            children.reserveCapacity(contents.count)

            for child in contents {
                if shouldCancel() { break }
                if let childNode = scan(child) {
                    childNode.parent = node
                    total += childNode.size
                    children.append(childNode)
                }
            }

            children.sort { $0.size > $1.size }
            node.children = children
            node.size = total
            fileCount += 1
            report(name)
            return node
        } else {
            let size = leafSize(values)
            fileCount += 1
            bytesScanned += size
            report(name)
            return FileNode(name: name, url: url, isDirectory: false, size: size)
        }
    }

    /// Prefer the true on-disk (allocated) size, matching what tools like
    /// DaisyDisk report; fall back to logical size when unavailable.
    private func leafSize(_ values: URLResourceValues?) -> Int64 {
        if let s = values?.totalFileAllocatedSize { return Int64(s) }
        if let s = values?.fileAllocatedSize { return Int64(s) }
        if let s = values?.fileSize { return Int64(s) }
        return 0
    }

    private func report(_ path: String) {
        if fileCount - lastReported >= 400 {
            lastReported = fileCount
            onProgress?(fileCount, bytesScanned, path)
        }
    }
}
