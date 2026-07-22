import Foundation
import Testing
@testable import FlareScan

@Suite("Memory Watch")
struct MemoryMonitorTests {
    @Test("tracks current, peak, average, growth, and ended apps")
    func sessionAggregation() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = MemorySession(startedAt: start)
        session.ingest([
            reading(id: "app.a", bytes: 1_000, active: true),
            reading(id: "app.b", bytes: 2_000)
        ], at: start)
        session.ingest([
            reading(id: "app.a", bytes: 1_500, active: true)
        ], at: start.addingTimeInterval(60))

        let snapshot = session.snapshot(referenceDate: start.addingTimeInterval(60))
        let appA = try #require(snapshot.apps.first { $0.id == "app.a" })
        let appB = try #require(snapshot.apps.first { $0.id == "app.b" })

        #expect(snapshot.sampleCount == 2)
        #expect(snapshot.totalCurrentBytes == 1_500)
        #expect(snapshot.totalPeakBytes == 3_000)
        #expect(snapshot.totalAverageBytes == 2_250)
        #expect(appA.currentBytes == 1_500)
        #expect(appA.peakBytes == 1_500)
        #expect(appA.averageBytes == 1_250)
        #expect(appA.changeBytes == 500)
        #expect(appA.foregroundObservedSeconds == 60)
        #expect(appB.currentBytes == 0)
        #expect(appB.peakBytes == 2_000)
        #expect(!appB.isRunning)
    }

    @Test("calculates a rolling last-hour summary")
    func rollingHour() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = MemorySession(startedAt: start)
        session.ingest([reading(id: "editor", bytes: 1_000)], at: start)
        session.ingest(
            [reading(id: "editor", bytes: 3_000)],
            at: start.addingTimeInterval(3_700))

        let stat = try #require(
            session.snapshot(referenceDate: start.addingTimeInterval(3_700))
                .apps.first)

        #expect(stat.peakBytes == 3_000)
        #expect(stat.averageBytes == 2_000)
        #expect(stat.lastHourPeakBytes == 3_000)
        #expect(stat.lastHourAverageBytes == 3_000)
    }

    @Test("protects Finder from quit recommendations")
    func protectsSystemApps() throws {
        let now = Date()
        var session = MemorySession(startedAt: now)
        session.ingest([
            reading(
                id: "com.apple.finder",
                bytes: 5_000_000_000,
                bundleIdentifier: "com.apple.finder",
                launchedAt: now.addingTimeInterval(-7_200))
        ], at: now)

        let finder = try #require(session.snapshot(referenceDate: now).apps.first)

        #expect(finder.attention == .high)
        #expect(!finder.canRequestQuit)
        #expect(!finder.shouldConsiderQuit)
    }

    @Test("does not count paused time as foreground usage")
    func pauseBreaksForegroundContinuity() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = MemorySession(startedAt: start)
        session.ingest([reading(id: "editor", bytes: 1_000, active: true)], at: start)
        session.breakSamplingContinuity()
        session.ingest(
            [reading(id: "editor", bytes: 1_200, active: true)],
            at: start.addingTimeInterval(3_600))

        let editor = try #require(
            session.snapshot(referenceDate: start.addingTimeInterval(3_600))
                .apps.first)

        #expect(editor.foregroundObservedSeconds == 0)
    }

    private func reading(
        id: String,
        bytes: Int64,
        bundleIdentifier: String? = nil,
        launchedAt: Date? = nil,
        active: Bool = false
    ) -> AppMemoryReading {
        AppMemoryReading(
            id: id,
            name: id,
            bundleIdentifier: bundleIdentifier ?? id,
            bundleURL: nil,
            residentBytes: bytes,
            processCount: 1,
            processIdentifiers: [42],
            launchedAt: launchedAt,
            isActive: active,
            isHidden: false)
    }
}
