import Foundation
import Testing
@testable import FlareScan

@Suite("Filesystem scanner")
struct ScannerTests {
    @Test("records a diagnostic instead of inventing a node for an unreadable path")
    func recordsReadFailure() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("flare-scan-missing-\(UUID().uuidString)")
        let scanner = Scanner()

        let result = scanner.scan(missing)

        #expect(result == nil)
        #expect(scanner.issueCount == 1)
        #expect(scanner.issues.count == 1)
        #expect(scanner.issues[0].path == missing.path)
    }
}
