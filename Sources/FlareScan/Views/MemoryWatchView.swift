import AppKit
import SwiftUI

struct MemoryWatchView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case running = "Running Now"
        case session = "Session History"

        var id: String { rawValue }
    }

    @EnvironmentObject private var app: AppState
    @State private var scope: Scope = .running

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                overview
                privacyBanner
                applicationsSection
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text("Memory Watch")
                        .font(.largeTitle.bold())
                    Circle()
                        .fill(app.memoryMonitorEnabled ? Color.green : Color.secondary)
                        .frame(width: 9, height: 9)
                        .help(app.memoryMonitorEnabled ? "Monitor is active" : "Monitor is paused")
                }
                Text("Track GUI app memory, child processes, session peaks, and the last-hour trend.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.isSamplingMemory {
                ProgressView().controlSize(.small)
            }
            Button {
                app.refreshMemoryNow()
            } label: {
                Label("Measure Now", systemImage: "arrow.clockwise")
            }
            .disabled(app.isSamplingMemory)
            Menu {
                ForEach(MemoryMonitorInterval.allCases) { interval in
                    Button {
                        app.setMemoryMonitorInterval(interval)
                    } label: {
                        if app.memoryMonitorInterval == interval {
                            Label(interval.title, systemImage: "checkmark")
                        } else {
                            Text(interval.title)
                        }
                    }
                }
            } label: {
                Label(app.memoryMonitorInterval.title, systemImage: "timer")
            }
            Button(app.memoryMonitorEnabled ? "Pause" : "Start") {
                if app.memoryMonitorEnabled {
                    app.stopMemoryMonitoring()
                } else {
                    app.startMemoryMonitoring()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(app.memoryMonitorEnabled ? .orange : .blue)
        }
    }

    private var overview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MemoryMetricCard(
                    title: "Tracked Memory Now",
                    value: ByteFormat.string(app.memoryTotalCurrentBytes),
                    detail: "\(runningApps.count) GUI apps",
                    icon: "memorychip.fill",
                    tint: .blue)
                MemoryMetricCard(
                    title: "Session peak",
                    value: ByteFormat.string(app.memoryTotalPeakBytes),
                    detail: "Since the monitor started",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .orange)
                MemoryMetricCard(
                    title: "Session Average",
                    value: ByteFormat.string(app.memoryTotalAverageBytes),
                    detail: "\(app.memorySampleCount) measurements",
                    icon: "equal.circle.fill",
                    tint: .indigo)
                MemoryMetricCard(
                    title: "Session Duration",
                    value: duration(Date().timeIntervalSince(app.memorySessionStartedAt)),
                    detail: lastSampleText,
                    icon: "clock.fill",
                    tint: .green)
            }
            MemorySparkline(points: app.memoryTotalPoints, tint: .blue)
                .frame(height: 72)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var privacyBanner: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Lightweight, local monitoring")
                    .font(.headline)
                Text("The default interval is one minute. Only app names, process counts, and resident-memory totals are kept in memory. Window titles, documents, typed text, and file contents are never read. Session history disappears when Flare Scan quits.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset Session", role: .destructive) {
                app.resetMemorySession()
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Applications")
                        .font(.title2.bold())
                    Text("Memory includes the app's main process and observable child processes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if app.memoryAccessUnavailable {
                ContentUnavailableView(
                    "Memory Access Unavailable",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("This build can see running apps but macOS is blocking their memory metrics. Use the standard-permission GitHub build instead of an App Sandbox build."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if visibleApps.isEmpty {
                ContentUnavailableView(
                    app.memoryMonitorEnabled ? "Waiting for a Measurement" : "Memory Watch Is Paused",
                    systemImage: "memorychip",
                    description: Text(app.memoryMonitorEnabled
                        ? "The first memory measurement is being prepared."
                        : "Start the monitor to resume periodic measurements."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleApps) { stat in
                        MemoryAppRow(stat: stat)
                        if stat.id != visibleApps.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            }

            Text("Resident memory is a point-in-time estimate. It can differ from Activity Monitor because macOS dynamically compresses and shares memory. Recommendations are investigation hints; high memory alone does not prove that an app is misbehaving.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runningApps: [MemoryAppStat] {
        app.memoryApps.filter(\.isRunning)
    }

    private var visibleApps: [MemoryAppStat] {
        switch scope {
        case .running:
            return runningApps.sorted { $0.currentBytes > $1.currentBytes }
        case .session:
            return app.memoryApps.sorted { lhs, rhs in
                if lhs.peakBytes == rhs.peakBytes { return lhs.name < rhs.name }
                return lhs.peakBytes > rhs.peakBytes
            }
        }
    }

    private var lastSampleText: String {
        guard let date = app.memoryLastSampleAt else { return "Waiting for first sample" }
        return "Last sample \(date.formatted(date: .omitted, time: .standard))"
    }
}

private struct MemoryMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MemoryAppRow: View {
    @EnvironmentObject private var app: AppState
    let stat: MemoryAppStat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                appIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(stat.name).font(.headline)
                        if stat.isActive {
                            Text("ACTIVE")
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                        } else if !stat.isRunning {
                            Text("CLOSED")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                MemorySparkline(points: stat.points, tint: attentionColor)
                    .frame(width: 120, height: 34)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stat.isRunning ? ByteFormat.string(stat.currentBytes) : "—")
                        .font(.title3.monospacedDigit().weight(.bold))
                    if stat.isRunning, stat.changeBytes != 0 {
                        Text(signedBytes(stat.changeBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(stat.changeBytes > 0 ? .orange : .green)
                    } else {
                        Text("peak \(ByteFormat.string(stat.peakBytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 118, alignment: .trailing)
                if stat.canRequestQuit {
                    Button("Quit", role: .destructive) { app.requestQuit(stat) }
                        .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 18) {
                statLabel("Session avg", ByteFormat.string(stat.averageBytes))
                statLabel("Last-hour peak", ByteFormat.string(stat.lastHourPeakBytes))
                statLabel("Last-hour avg", ByteFormat.string(stat.lastHourAverageBytes))
                statLabel("Foreground", duration(stat.foregroundObservedSeconds))
                Spacer()
                if stat.attention != .normal {
                    Label(recommendation, systemImage: stat.attention == .high
                        ? "exclamationmark.triangle.fill"
                        : "eye.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(attentionColor)
                }
            }
        }
        .padding(.vertical, 13)
        .opacity(stat.isRunning ? 1 : 0.62)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = stat.bundleURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
        }
    }

    private var metadata: String {
        var pieces: [String] = []
        if stat.isRunning {
            pieces.append("\(stat.processCount) process")
        }
        if let launchedAt = stat.launchedAt {
            pieces.append("running for \(duration(Date().timeIntervalSince(launchedAt)))")
        }
        pieces.append("\(stat.sampleCount) samples")
        return pieces.joined(separator: " · ")
    }

    private var recommendation: String {
        if stat.shouldConsiderQuit {
            return "High background memory — consider quitting after saving your work"
        }
        if stat.attention == .high { return "Very high current memory — review this app's activity" }
        return "Memory grew quickly — keep an eye on the trend"
    }

    private var attentionColor: Color {
        switch stat.attention {
        case .normal: return .blue
        case .review: return .orange
        case .high: return .red
        }
    }

    private func statLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }

    private func signedBytes(_ value: Int64) -> String {
        value > 0 ? "+\(ByteFormat.string(value))" : "−\(ByteFormat.string(abs(value)))"
    }
}

private struct MemorySparkline: View {
    let points: [MemoryPoint]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let visible = recentPoints
            guard !visible.isEmpty else { return }
            let maximum = max(visible.map(\.bytes).max() ?? 1, 1)
            let minimum = min(visible.map(\.bytes).min() ?? 0, maximum)
            let span = max(maximum - minimum, 1)
            var path = Path()
            for (index, point) in visible.enumerated() {
                let x = visible.count == 1
                    ? size.width
                    : size.width * CGFloat(index) / CGFloat(visible.count - 1)
                let fraction = CGFloat(point.bytes - minimum) / CGFloat(span)
                let y = size.height - (fraction * max(1, size.height - 4)) - 2
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(tint), lineWidth: 2)
        }
        .accessibilityLabel("Last-hour memory trend")
    }

    private var recentPoints: [MemoryPoint] {
        let cutoff = Date().addingTimeInterval(-3_600)
        return points.filter { $0.timestamp >= cutoff }
    }
}

struct MemoryMenuBarView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "memorychip.fill").foregroundStyle(.blue)
                Text("Flare Scan Memory Watch").font(.headline)
                Spacer()
                Circle()
                    .fill(app.memoryMonitorEnabled ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(ByteFormat.string(app.memoryTotalCurrentBytes))
                    .font(.title2.monospacedDigit().bold())
                Text("tracked memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 7) {
                ForEach(topApps) { stat in
                    HStack {
                        Text(stat.name).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(stat.currentBytes))
                            .font(.callout.monospacedDigit().weight(.semibold))
                    }
                }
            }

            if topApps.isEmpty {
                Text(app.memoryMonitorEnabled ? "Preparing the first sample…" : "Monitor is paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button(app.memoryMonitorEnabled ? "Pause" : "Start") {
                    if app.memoryMonitorEnabled {
                        app.stopMemoryMonitoring()
                    } else {
                        app.startMemoryMonitoring()
                    }
                }
                Button("Measure Now") { app.refreshMemoryNow() }
                    .disabled(app.isSamplingMemory)
            }
            Button("Open Full Memory Watch") {
                app.mode = .memory
                openWindow(id: "main")
            }
            Divider()
            Button("Quit Flare Scan", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 330)
    }

    private var topApps: [MemoryAppStat] {
        Array(app.memoryApps.filter(\.isRunning).prefix(3))
    }
}

private func duration(_ seconds: TimeInterval) -> String {
    let safeSeconds = max(0, Int(seconds))
    let days = safeSeconds / 86_400
    let hours = (safeSeconds % 86_400) / 3_600
    let minutes = (safeSeconds % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "<1m"
}
