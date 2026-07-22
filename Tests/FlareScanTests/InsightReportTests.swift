import Foundation
import Testing
@testable import FlareScan

@Suite("Insights report export")
struct InsightReportTests {
    @Test("exports versioned JSON with summary data")
    func exportsJSON() throws {
        let fixture = makeFixture()
        let report = InsightReport(
            root: fixture.root,
            insights: fixture.insights,
            duplicateGroups: [],
            scanIssueCount: 1,
            scanIssues: [ScanIssue(path: "/private", message: "Permission denied")],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try report.data(format: .json)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summary = try #require(object["summary"] as? [String: Any])

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["rootName"] as? String == "report")
        #expect(summary["fileCount"] as? Int == 1)
        #expect(summary["allocatedBytes"] as? Int == 300)
        #expect(summary["unreadableItems"] as? Int == 1)
        #expect((object["scanIssues"] as? [[String: Any]])?.count == 1)
    }

    @Test("CSV escapes paths and merges finding labels")
    func exportsCSV() throws {
        let fixture = makeFixture()
        let report = InsightReport(
            root: fixture.root,
            insights: fixture.insights,
            duplicateGroups: [])

        let csv = try #require(String(data: report.data(format: .csv), encoding: .utf8))

        #expect(csv.hasPrefix("findings,name,path,allocated_bytes"))
        #expect(csv.contains("largest+old_large"))
        #expect(csv.contains("\"movie,\"\"final\"\".mp4\""))
    }

    private func makeFixture() -> (root: FileNode, insights: ScanInsights) {
        let root = FileNode(
            name: "report",
            url: URL(fileURLWithPath: "/tmp/report"),
            isDirectory: true,
            size: 300,
            logicalSize: 280)
        let file = FileNode(
            name: "movie,\"final\".mp4",
            url: root.url.appendingPathComponent("movie,\"final\".mp4"),
            isDirectory: false,
            size: 300,
            logicalSize: 280,
            modifiedAt: Date(timeIntervalSince1970: 1_000_000_000),
            parent: root)
        root.children = [file]
        let insights = ScanInsights.build(
            from: root,
            oldMinimumSize: 1,
            oldThresholdDays: 1,
            referenceDate: Date(timeIntervalSince1970: 1_700_000_000))
        return (root, insights)
    }
}
