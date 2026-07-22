import Foundation
import Testing
@testable import FlareScan

@Suite("Storage insights")
struct ScanInsightsTests {
    @Test("classifies files, counts folders, and ranks largest files")
    func buildsInsights() {
        let root = FileNode(
            name: "root",
            url: URL(fileURLWithPath: "/tmp/root"),
            isDirectory: true,
            size: 1_000)
        let media = FileNode(
            name: "media",
            url: root.url.appendingPathComponent("media"),
            isDirectory: true,
            size: 800,
            parent: root)
        let movie = FileNode(
            name: "movie.mp4",
            url: media.url.appendingPathComponent("movie.mp4"),
            isDirectory: false,
            size: 700,
            parent: media)
        let image = FileNode(
            name: "photo.png",
            url: media.url.appendingPathComponent("photo.png"),
            isDirectory: false,
            size: 100,
            parent: media)
        let archive = FileNode(
            name: "backup.zip",
            url: root.url.appendingPathComponent("backup.zip"),
            isDirectory: false,
            size: 200,
            parent: root)
        media.children = [movie, image]
        root.children = [media, archive]

        let insights = ScanInsights.build(from: root, largestLimit: 2)

        #expect(insights.fileCount == 3)
        #expect(insights.directoryCount == 2)
        #expect(insights.largestFiles.map(\.name) == ["movie.mp4", "backup.zip"])
        #expect(insights.categories.map(\.category) == [.video, .archives, .images])
        #expect(insights.categories.first?.fraction == 0.7)
    }

    @Test("uses Other for unknown extensions")
    func classifiesUnknownExtension() {
        #expect(FileCategory.classify(URL(fileURLWithPath: "/tmp/blob.unknown")) == .other)
        #expect(FileCategory.classify(URL(fileURLWithPath: "/tmp/archive.dmg")) == .installers)
    }

    @Test("finds only large files older than the configured threshold")
    func findsOldLargeFiles() {
        let reference = Date(timeIntervalSince1970: 2_000_000_000)
        let root = FileNode(
            name: "root",
            url: URL(fileURLWithPath: "/tmp/root"),
            isDirectory: true,
            size: 500)
        let old = FileNode(
            name: "old.mov",
            url: root.url.appendingPathComponent("old.mov"),
            isDirectory: false,
            size: 300,
            modifiedAt: reference.addingTimeInterval(-200 * 86_400),
            parent: root)
        let recent = FileNode(
            name: "recent.mov",
            url: root.url.appendingPathComponent("recent.mov"),
            isDirectory: false,
            size: 200,
            modifiedAt: reference.addingTimeInterval(-10 * 86_400),
            parent: root)
        root.children = [old, recent]

        let insights = ScanInsights.build(
            from: root,
            oldMinimumSize: 100,
            oldThresholdDays: 180,
            referenceDate: reference)

        #expect(insights.oldLargeFiles.map(\.name) == ["old.mov"])
    }
}
