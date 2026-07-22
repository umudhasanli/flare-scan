import Foundation

/// Human-readable byte sizes (e.g. "1.2 GB"), using the same base-10 file
/// convention Finder uses.
enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
