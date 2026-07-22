import Foundation

enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case video, images, audio, archives, documents, code, installers, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "Video"
        case .images: return "Images"
        case .audio: return "Audio"
        case .archives: return "Archives"
        case .documents: return "Documents"
        case .code: return "Code"
        case .installers: return "Installers"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .video: return "film"
        case .images: return "photo"
        case .audio: return "waveform"
        case .archives: return "archivebox"
        case .documents: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .installers: return "shippingbox"
        case .other: return "doc"
        }
    }

    static func classify(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .images }
        if audioExtensions.contains(ext) { return .audio }
        if archiveExtensions.contains(ext) { return .archives }
        if documentExtensions.contains(ext) { return .documents }
        if codeExtensions.contains(ext) { return .code }
        if installerExtensions.contains(ext) { return .installers }
        return .other
    }

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "mpeg", "mpg"
    ]
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif",
        "webp", "svg", "raw", "cr2", "nef", "dng", "psd"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg", "opus"
    ]
    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"
    ]
    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages",
        "numbers", "key", "txt", "rtf", "md", "csv", "epub"
    ]
    private static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "go", "rs", "py",
        "js", "mjs", "cjs", "ts", "tsx", "jsx", "java", "kt", "rb",
        "php", "html", "css", "scss", "json", "yaml", "yml", "toml", "xml"
    ]
    private static let installerExtensions: Set<String> = [
        "dmg", "pkg", "iso", "img", "xip"
    ]
}

struct CategorySummary: Identifiable, Sendable {
    let category: FileCategory
    let bytes: Int64
    let fileCount: Int
    let totalBytes: Int64

    var id: String { category.id }
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytes) / Double(totalBytes)
    }
}

struct ScanInsights: @unchecked Sendable {
    let fileCount: Int
    let directoryCount: Int
    let largestFiles: [FileNode]
    let oldLargeFiles: [FileNode]
    let categories: [CategorySummary]

    static func build(
        from root: FileNode,
        largestLimit: Int = 50,
        oldLimit: Int = 50,
        oldMinimumSize: Int64 = 104_857_600,
        oldThresholdDays: Int = 180,
        referenceDate: Date = Date()
    ) -> ScanInsights {
        var fileCount = 0
        var largestFiles: [FileNode] = []
        var oldLargeFiles: [FileNode] = []
        var directoryCount = 0
        var categoryBytes: [FileCategory: Int64] = [:]
        var categoryCounts: [FileCategory: Int] = [:]
        var stack = [root]
        let oldCutoff = Calendar.current.date(
            byAdding: .day,
            value: -oldThresholdDays,
            to: referenceDate) ?? referenceDate

        while let node = stack.popLast() {
            if node.isDirectory {
                directoryCount += 1
                stack.append(contentsOf: node.children)
            } else {
                fileCount += 1
                if largestLimit > 0 {
                    insert(node, into: &largestFiles, limit: largestLimit)
                }
                if oldLimit > 0,
                   node.size >= oldMinimumSize,
                   let modifiedAt = node.modifiedAt,
                   modifiedAt < oldCutoff {
                    insert(node, into: &oldLargeFiles, limit: oldLimit)
                }
                let category = FileCategory.classify(node.url)
                categoryBytes[category, default: 0] += node.size
                categoryCounts[category, default: 0] += 1
            }
        }

        let categories = FileCategory.allCases.compactMap { category -> CategorySummary? in
            guard let bytes = categoryBytes[category], bytes > 0 else { return nil }
            return CategorySummary(
                category: category,
                bytes: bytes,
                fileCount: categoryCounts[category, default: 0],
                totalBytes: root.size)
        }.sorted { $0.bytes > $1.bytes }

        return ScanInsights(
            fileCount: fileCount,
            directoryCount: directoryCount,
            largestFiles: largestFiles,
            oldLargeFiles: oldLargeFiles,
            categories: categories)
    }

    private static func insert(_ node: FileNode, into files: inout [FileNode], limit: Int) {
        files.append(node)
        files.sort(by: isLarger)
        if files.count > limit { files.removeLast() }
    }

    private static func isLarger(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        if lhs.size == rhs.size { return lhs.url.path < rhs.url.path }
        return lhs.size > rhs.size
    }
}
