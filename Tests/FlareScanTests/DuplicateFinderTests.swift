import Foundation
import Testing
@testable import FlareScan

@Suite("Duplicate finder")
struct DuplicateFinderTests {
    @Test("requires identical content, not just identical size")
    func findsExactDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flare-scan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.bin")
        let secondURL = directory.appendingPathComponent("second.bin")
        let differentURL = directory.appendingPathComponent("different.bin")
        let duplicateData = Data("same-content".utf8)
        try duplicateData.write(to: firstURL)
        try duplicateData.write(to: secondURL)
        try Data("other-bytes!".utf8).write(to: differentURL)

        let root = FileNode(
            name: directory.lastPathComponent,
            url: directory,
            isDirectory: true,
            size: 36,
            logicalSize: 36)
        let files = [firstURL, secondURL, differentURL].map { url in
            FileNode(
                name: url.lastPathComponent,
                url: url,
                isDirectory: false,
                size: 12,
                logicalSize: 12,
                parent: root)
        }
        root.children = files

        let groups = DuplicateFinder.find(in: root, minimumSize: 1)

        #expect(groups.count == 1)
        #expect(Set(groups[0].files.map(\.name)) == Set(["first.bin", "second.bin"]))
        #expect(groups[0].reclaimableSize == 12)
    }

    @Test("honors the minimum file size")
    func skipsSmallFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flare-scan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let urls = ["a.bin", "b.bin"].map { directory.appendingPathComponent($0) }
        for url in urls { try Data("tiny".utf8).write(to: url) }
        let root = FileNode(name: "root", url: directory, isDirectory: true, size: 8)
        root.children = urls.map {
            FileNode(name: $0.lastPathComponent, url: $0, isDirectory: false,
                     size: 4, logicalSize: 4, parent: root)
        }

        #expect(DuplicateFinder.find(in: root, minimumSize: 5).isEmpty)
    }
}
