import Foundation

struct ScanIssue: Identifiable, Sendable {
    let path: String
    let message: String

    var id: String { "\(path)\u{0}\(message)" }
}
