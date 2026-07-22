import Foundation

/// One node in the scanned file tree.
///
/// Directories aggregate the on-disk size of all their descendants; files
/// carry their own allocated size. The tree is built once by `Scanner` and then
/// only read from the main actor, so `@unchecked Sendable` is safe here.
final class FileNode: Identifiable, @unchecked Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    let modifiedAt: Date?
    /// Logical byte length. Used for exact duplicate candidate grouping.
    var logicalSize: Int64
    /// Allocated on-disk size used by the visualizations and reclaim estimates.
    var size: Int64
    var children: [FileNode]
    weak var parent: FileNode?

    init(name: String,
         url: URL,
         isDirectory: Bool,
         size: Int64,
         logicalSize: Int64? = nil,
         modifiedAt: Date? = nil,
         children: [FileNode] = [],
         parent: FileNode? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.logicalSize = logicalSize ?? size
        self.modifiedAt = modifiedAt
        self.children = children
        self.parent = parent
    }

    /// A readable name, falling back to the last path component for volumes.
    var displayName: String {
        name.isEmpty ? url.lastPathComponent : name
    }

    /// Root → self chain, used to render the breadcrumb.
    var ancestryFromRoot: [FileNode] {
        var chain: [FileNode] = []
        var node: FileNode? = self
        while let current = node {
            chain.insert(current, at: 0)
            node = current.parent
        }
        return chain
    }

    /// The fraction of the parent's size this node occupies (0...1).
    var fractionOfParent: Double {
        guard let parent, parent.size > 0 else { return 1 }
        return Double(size) / Double(parent.size)
    }
}
