import AppKit
import Darwin
import Foundation

enum MemoryMonitorInterval: TimeInterval, CaseIterable, Identifiable, Sendable {
    case fifteenSeconds = 15
    case oneMinute = 60
    case fiveMinutes = 300

    var id: TimeInterval { rawValue }

    var title: String {
        switch self {
        case .fifteenSeconds: return "15 sec"
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        }
    }
}

struct AppMemoryReading: Identifiable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let residentBytes: Int64
    let processCount: Int
    let processIdentifiers: [pid_t]
    let launchedAt: Date?
    let isActive: Bool
    let isHidden: Bool
}

struct MemoryPoint: Identifiable, Sendable {
    let timestamp: Date
    let bytes: Int64

    var id: Date { timestamp }
}

enum MemoryAttention: Int, Comparable, Sendable {
    case normal, review, high

    static func < (lhs: MemoryAttention, rhs: MemoryAttention) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MemoryAppStat: Identifiable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let currentBytes: Int64
    let peakBytes: Int64
    let averageBytes: Int64
    let lastHourPeakBytes: Int64
    let lastHourAverageBytes: Int64
    let changeBytes: Int64
    let processCount: Int
    let processIdentifiers: [pid_t]
    let launchedAt: Date?
    let firstSeenAt: Date
    let lastSeenAt: Date
    let foregroundObservedSeconds: TimeInterval
    let sampleCount: Int
    let isActive: Bool
    let isHidden: Bool
    let isRunning: Bool
    let points: [MemoryPoint]

    var canRequestQuit: Bool {
        guard isRunning, !processIdentifiers.isEmpty else { return false }
        let protectedIdentifiers: Set<String> = [
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.systemuiserver",
            "com.apple.WindowManager"
        ]
        return bundleIdentifier.map { !protectedIdentifiers.contains($0) } ?? true
    }

    var attention: MemoryAttention {
        guard isRunning else { return .normal }
        if currentBytes >= 4_294_967_296 { return .high }
        if currentBytes >= 1_610_612_736 && !isActive { return .review }
        if changeBytes >= 536_870_912 { return .review }
        return .normal
    }

    var shouldConsiderQuit: Bool {
        guard canRequestQuit, !isActive, currentBytes >= 1_073_741_824 else {
            return false
        }
        guard let launchedAt else { return true }
        return Date().timeIntervalSince(launchedAt) >= 1_800
    }
}

struct MemorySessionSnapshot: Sendable {
    let startedAt: Date
    let lastSampleAt: Date?
    let sampleCount: Int
    let totalCurrentBytes: Int64
    let totalPeakBytes: Int64
    let totalAverageBytes: Int64
    let totalPoints: [MemoryPoint]
    let apps: [MemoryAppStat]
}

struct MemorySession: Sendable {
    private struct Accumulator: Sendable {
        var name: String
        var bundleIdentifier: String?
        var bundleURL: URL?
        var currentBytes: Int64 = 0
        var peakBytes: Int64 = 0
        var sumBytes: Double = 0
        var changeBytes: Int64 = 0
        var processCount: Int = 0
        var processIdentifiers: [pid_t] = []
        var launchedAt: Date?
        let firstSeenAt: Date
        var lastSeenAt: Date
        var foregroundObservedSeconds: TimeInterval = 0
        var sampleCount: Int = 0
        var isActive: Bool = false
        var isHidden: Bool = false
        var isRunning: Bool = false
        var wasRunning = false
        var previousBytes: Int64 = 0
        var points: [MemoryPoint] = []

        mutating func prepareForSample() {
            wasRunning = isRunning
            previousBytes = currentBytes
            currentBytes = 0
            processCount = 0
            processIdentifiers = []
            isActive = false
            isHidden = false
            isRunning = false
            changeBytes = 0
        }

        mutating func ingest(
            _ reading: AppMemoryReading,
            at date: Date,
            foregroundIncrement: TimeInterval
        ) {
            name = reading.name
            bundleIdentifier = reading.bundleIdentifier
            bundleURL = reading.bundleURL
            currentBytes = reading.residentBytes
            peakBytes = max(peakBytes, reading.residentBytes)
            sumBytes += Double(reading.residentBytes)
            changeBytes = wasRunning ? reading.residentBytes - previousBytes : 0
            processCount = reading.processCount
            processIdentifiers = reading.processIdentifiers
            launchedAt = reading.launchedAt
            lastSeenAt = date
            sampleCount += 1
            isActive = reading.isActive
            isHidden = reading.isHidden
            isRunning = true
            if reading.isActive {
                foregroundObservedSeconds += foregroundIncrement
            }
            points.append(MemoryPoint(timestamp: date, bytes: reading.residentBytes))
            trimPoints(referenceDate: date)
        }

        mutating func trimPoints(referenceDate: Date) {
            let cutoff = referenceDate.addingTimeInterval(-86_400)
            points.removeAll { $0.timestamp < cutoff }
            if points.count > 5_760 {
                points.removeFirst(points.count - 5_760)
            }
        }

        func stat(referenceDate: Date) -> MemoryAppStat {
            let hourCutoff = referenceDate.addingTimeInterval(-3_600)
            let hourPoints = points.filter { $0.timestamp >= hourCutoff }
            let hourPeak = hourPoints.map(\.bytes).max() ?? 0
            let hourAverage: Int64
            if hourPoints.isEmpty {
                hourAverage = 0
            } else {
                hourAverage = Int64(
                    hourPoints.reduce(0.0) { $0 + Double($1.bytes) }
                        / Double(hourPoints.count))
            }
            return MemoryAppStat(
                id: bundleIdentifier ?? bundleURL?.path ?? name,
                name: name,
                bundleIdentifier: bundleIdentifier,
                bundleURL: bundleURL,
                currentBytes: currentBytes,
                peakBytes: peakBytes,
                averageBytes: sampleCount == 0 ? 0 : Int64(sumBytes / Double(sampleCount)),
                lastHourPeakBytes: hourPeak,
                lastHourAverageBytes: hourAverage,
                changeBytes: changeBytes,
                processCount: processCount,
                processIdentifiers: processIdentifiers,
                launchedAt: launchedAt,
                firstSeenAt: firstSeenAt,
                lastSeenAt: lastSeenAt,
                foregroundObservedSeconds: foregroundObservedSeconds,
                sampleCount: sampleCount,
                isActive: isActive,
                isHidden: isHidden,
                isRunning: isRunning,
                points: points)
        }
    }

    let startedAt: Date
    private var lastSampleAt: Date?
    private var lastForegroundSampleAt: Date?
    private var sampleCount = 0
    private var totalPeakBytes: Int64 = 0
    private var totalSumBytes: Double = 0
    private var totalPoints: [MemoryPoint] = []
    private var apps: [String: Accumulator] = [:]

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func ingest(_ readings: [AppMemoryReading], at date: Date = Date()) {
        let elapsed: TimeInterval
        if let lastForegroundSampleAt {
            elapsed = min(max(0, date.timeIntervalSince(lastForegroundSampleAt)), 300)
        } else {
            elapsed = 0
        }

        for key in Array(apps.keys) {
            apps[key]?.prepareForSample()
        }

        for reading in readings {
            var accumulator = apps[reading.id] ?? Accumulator(
                name: reading.name,
                bundleIdentifier: reading.bundleIdentifier,
                bundleURL: reading.bundleURL,
                firstSeenAt: date,
                lastSeenAt: date)
            accumulator.ingest(reading, at: date, foregroundIncrement: elapsed)
            apps[reading.id] = accumulator
        }

        let total = readings.reduce(Int64(0)) { partial, reading in
            let (sum, overflow) = partial.addingReportingOverflow(reading.residentBytes)
            return overflow ? Int64.max : sum
        }
        totalPeakBytes = max(totalPeakBytes, total)
        totalSumBytes += Double(total)
        totalPoints.append(MemoryPoint(timestamp: date, bytes: total))
        let cutoff = date.addingTimeInterval(-86_400)
        totalPoints.removeAll { $0.timestamp < cutoff }
        if totalPoints.count > 5_760 {
            totalPoints.removeFirst(totalPoints.count - 5_760)
        }
        sampleCount += 1
        lastSampleAt = date
        lastForegroundSampleAt = date
    }

    mutating func breakSamplingContinuity() {
        lastForegroundSampleAt = nil
    }

    func snapshot(referenceDate: Date = Date()) -> MemorySessionSnapshot {
        let stats = apps.values.map { $0.stat(referenceDate: referenceDate) }
            .sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
                if lhs.currentBytes == rhs.currentBytes { return lhs.name < rhs.name }
                return lhs.currentBytes > rhs.currentBytes
            }
        return MemorySessionSnapshot(
            startedAt: startedAt,
            lastSampleAt: lastSampleAt,
            sampleCount: sampleCount,
            totalCurrentBytes: totalPoints.last?.bytes ?? 0,
            totalPeakBytes: totalPeakBytes,
            totalAverageBytes: sampleCount == 0 ? 0 : Int64(totalSumBytes / Double(sampleCount)),
            totalPoints: totalPoints,
            apps: stats)
    }
}

enum MemorySampler {
    private struct ProcessRecord {
        let parentPID: pid_t
        let residentBytes: Int64
    }

    private struct ReadingBuilder {
        var name: String
        var bundleIdentifier: String?
        var bundleURL: URL?
        var residentBytes: Int64 = 0
        var processCount = 0
        var processIdentifiers: [pid_t] = []
        var launchedAt: Date?
        var isActive = false
        var isHidden = true
    }

    static func sample() -> [AppMemoryReading] {
        let ownPID = Foundation.ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated
                && $0.activationPolicy == .regular
                && $0.processIdentifier > 0
                && $0.processIdentifier != ownPID
        }
        let roots = Set(applications.map(\.processIdentifier))
        let processInfo = allProcessInfo()
        var rootTotals: [pid_t: (bytes: Int64, count: Int)] = [:]

        for (pid, info) in processInfo {
            guard let rootPID = owningRoot(
                for: pid,
                roots: roots,
                processes: processInfo) else { continue }
            let old = rootTotals[rootPID] ?? (0, 0)
            let (sum, overflow) = old.bytes.addingReportingOverflow(info.residentBytes)
            rootTotals[rootPID] = (overflow ? Int64.max : sum, old.count + 1)
        }

        var builders: [String: ReadingBuilder] = [:]
        for application in applications {
            let identifier = application.bundleIdentifier
                ?? application.bundleURL?.path
                ?? "pid:\(application.processIdentifier)"
            let totals = rootTotals[application.processIdentifier] ?? (0, 0)
            var builder = builders[identifier] ?? ReadingBuilder(
                name: application.localizedName ?? "Unknown App",
                bundleIdentifier: application.bundleIdentifier,
                bundleURL: application.bundleURL,
                launchedAt: application.launchDate)
            let (sum, overflow) = builder.residentBytes.addingReportingOverflow(totals.bytes)
            builder.residentBytes = overflow ? Int64.max : sum
            builder.processCount += totals.count
            builder.processIdentifiers.append(application.processIdentifier)
            if let launchDate = application.launchDate {
                builder.launchedAt = min(builder.launchedAt ?? launchDate, launchDate)
            }
            builder.isActive = builder.isActive || application.isActive
            builder.isHidden = builder.isHidden && application.isHidden
            builders[identifier] = builder
        }

        return builders.map { identifier, builder in
            AppMemoryReading(
                id: identifier,
                name: builder.name,
                bundleIdentifier: builder.bundleIdentifier,
                bundleURL: builder.bundleURL,
                residentBytes: builder.residentBytes,
                processCount: builder.processCount,
                processIdentifiers: builder.processIdentifiers,
                launchedAt: builder.launchedAt,
                isActive: builder.isActive,
                isHidden: builder.isHidden)
        }
    }

    private static func allProcessInfo() -> [pid_t: ProcessRecord] {
        let requestedCount = max(0, Int(proc_listallpids(nil, 0)))
        guard requestedCount > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: requestedCount + 32)
        let actualCount = proc_listallpids(
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actualCount > 0 else { return [:] }

        var result: [pid_t: ProcessRecord] = [:]
        for pid in pids.prefix(Int(actualCount)) where pid > 0 {
            var info = proc_taskallinfo()
            let bytes = proc_pidinfo(
                pid,
                PROC_PIDTASKALLINFO,
                0,
                &info,
                Int32(MemoryLayout<proc_taskallinfo>.size))
            guard bytes == Int32(MemoryLayout<proc_taskallinfo>.size) else { continue }
            result[pid] = ProcessRecord(
                parentPID: pid_t(info.pbsd.pbi_ppid),
                residentBytes: Int64(clamping: info.ptinfo.pti_resident_size))
        }
        return result
    }

    private static func owningRoot(
        for pid: pid_t,
        roots: Set<pid_t>,
        processes: [pid_t: ProcessRecord]
    ) -> pid_t? {
        var cursor = pid
        var visited: Set<pid_t> = []
        while cursor > 0, visited.insert(cursor).inserted {
            if roots.contains(cursor) { return cursor }
            guard let info = processes[cursor] else { return nil }
            cursor = info.parentPID
        }
        return nil
    }
}
