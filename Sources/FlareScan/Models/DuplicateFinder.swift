import CryptoKit
import Foundation

struct DuplicateGroup: Identifiable, @unchecked Sendable {
    let id: String
    let logicalSize: Int64
    let files: [FileNode]

    var reclaimableSize: Int64 {
        files.dropFirst().reduce(0) { $0 + $1.size }
    }
}

enum DuplicateFinder {
    /// Finds byte-for-byte identical files without sending names or contents
    /// anywhere. Size grouping avoids hashing files that cannot be duplicates.
    static func find(
        in root: FileNode,
        minimumSize: Int64 = 1_048_576,
        shouldCancel: () -> Bool = { false },
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> [DuplicateGroup] {
        var bySize: [Int64: [FileNode]] = [:]
        var stack = [root]
        while let node = stack.popLast() {
            if shouldCancel() { return [] }
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else if node.logicalSize >= minimumSize {
                bySize[node.logicalSize, default: []].append(node)
            }
        }

        let candidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        var hashed = 0
        var exact: [String: [FileNode]] = [:]

        for node in candidates {
            if shouldCancel() { return [] }
            if let digest = try? digest(of: node.url, shouldCancel: shouldCancel) {
                exact["\(node.logicalSize):\(digest)", default: []].append(node)
            }
            hashed += 1
            onProgress?(hashed, candidates.count)
        }

        return exact.compactMap { signature, files in
            guard files.count > 1, let first = files.first else { return nil }
            return DuplicateGroup(
                id: signature,
                logicalSize: first.logicalSize,
                files: files.sorted { $0.url.path < $1.url.path })
        }.sorted { lhs, rhs in
            if lhs.reclaimableSize == rhs.reclaimableSize {
                return lhs.files[0].url.path < rhs.files[0].url.path
            }
            return lhs.reclaimableSize > rhs.reclaimableSize
        }
    }

    private static func digest(of url: URL, shouldCancel: () -> Bool) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while !shouldCancel() {
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else {
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            }
            hasher.update(data: data)
        }
        throw CancellationError()
    }
}
