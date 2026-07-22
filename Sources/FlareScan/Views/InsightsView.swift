import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var app: AppState
    let insights: ScanInsights

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                summaryCards
                scanQualitySection
                historySection
                categorySection
                largestFilesSection
                oldLargeFilesSection
                duplicatesSection
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Storage Insights")
                    .font(.largeTitle.bold())
                Text("See the largest files, storage categories, and exact duplicates in one place.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.isExportingReport {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing report…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if app.lastExportURL != nil {
                Button("Show Report in Finder") { app.revealLastExport() }
            }
            Menu {
                Button("JSON Report") { app.exportInsights(as: .json) }
                Button("CSV Report") { app.exportInsights(as: .csv) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(app.isExportingReport)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            MetricCard(
                title: "Allocated Space",
                value: ByteFormat.string(app.root?.size ?? 0),
                icon: "internaldrive.fill",
                tint: .blue)
            MetricCard(
                title: "Files",
                value: insights.fileCount.formatted(),
                icon: "doc.on.doc",
                tint: .indigo)
            MetricCard(
                title: "Folders",
                value: insights.directoryCount.formatted(),
                icon: "folder.fill",
                tint: .orange)
            MetricCard(
                title: "Duplicate Savings",
                value: app.duplicateGroups == nil ? "Not analyzed" : ByteFormat.string(app.duplicateReclaimableBytes),
                icon: "square.on.square",
                tint: .green)
        }
    }

    @ViewBuilder
    private var scanQualitySection: some View {
        if app.scanIssueCount == 0 {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                Text("Scan complete — no unreadable items were recorded.")
                    .font(.callout)
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(app.scanIssues) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(issue.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if app.scanIssueCount > app.scanIssues.count {
                        Text("\((app.scanIssueCount - app.scanIssues.count).formatted()) additional errors are included in the report count.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(
                    "\(app.scanIssueCount.formatted()) items were unreadable — results may be incomplete",
                    systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var categorySection: some View {
        InsightSection(title: "Categories", subtitle: "Allocated disk space grouped by file type") {
            VStack(spacing: 11) {
                ForEach(Array(insights.categories.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.category.systemImage)
                            .foregroundStyle(Palette.color(hue: Palette.hue(forIndex: index), depth: 1))
                            .frame(width: 22)
                        Text(item.category.title)
                            .frame(width: 92, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.12))
                                Capsule()
                                    .fill(Palette.color(hue: Palette.hue(forIndex: index), depth: 1))
                                    .frame(width: max(3, geometry.size.width * item.fraction))
                            }
                        }
                        .frame(height: 8)
                        Text("\(item.fileCount.formatted()) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 82, alignment: .trailing)
                        Text(ByteFormat.string(item.bytes))
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .frame(width: 86, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        InsightSection(
            title: "What Changed?",
            subtitle: "See which files filled or freed storage between scans"
        ) {
            if app.isSavingBaseline {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Updating the local baseline…")
                        .foregroundStyle(.secondary)
                }
            } else if !app.hasSavedBaseline {
                HStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save this scan as a baseline")
                            .font(.headline)
                        Text("The next scan of this location will reveal large files that appeared, grew, shrank, or disappeared.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save Baseline") { app.saveCurrentScanAsBaseline() }
                        .buttonStyle(.borderedProminent)
                }
            } else if let delta = app.scanDelta {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(
                            "Baseline: \(delta.baselineDate.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: "clock.badge.checkmark")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Update Baseline") { app.saveCurrentScanAsBaseline() }
                        Button("Forget", role: .destructive) { app.forgetSavedBaseline() }
                    }

                    HStack(spacing: 10) {
                        ChangeMetric(
                            title: "Net Change",
                            value: signedBytes(delta.netAllocatedChange),
                            tint: delta.netAllocatedChange > 0 ? .orange : .green)
                        ChangeMetric(title: "New Files", value: ByteFormat.string(delta.addedBytes), tint: .blue)
                        ChangeMetric(title: "Files That Grew", value: ByteFormat.string(delta.grownBytes), tint: .orange)
                        ChangeMetric(title: "Space Released", value: ByteFormat.string(delta.releasedBytes), tint: .green)
                    }

                    if delta.changes.isEmpty {
                        ContentUnavailableView(
                            "No Large Changes",
                            systemImage: "checkmark.circle",
                            description: Text("Tracked files larger than 1 MB have not changed since the baseline."))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(delta.changes) { change in
                                StorageChangeRow(change: change)
                                if change.id != delta.changes.last?.id { Divider() }
                            }
                        }
                    }

                    if delta.baselineWasTruncated || delta.currentWasTruncated {
                        Label(
                            "The snapshot is capped at the 50,000 largest files; small changes may be omitted in very large trees.",
                            systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Baseline saved for this scan")
                            .font(.headline)
                        if let date = app.baselineSavedAt {
                            Text("\(date.formatted(date: .abbreviated, time: .shortened)) · Scan this location again later to see what changed.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Update Baseline") { app.saveCurrentScanAsBaseline() }
                    Button("Forget", role: .destructive) { app.forgetSavedBaseline() }
                }
            }
        }
    }

    private func signedBytes(_ value: Int64) -> String {
        if value > 0 { return "+\(ByteFormat.string(value))" }
        if value < 0 { return "−\(ByteFormat.string(abs(value)))" }
        return ByteFormat.string(0)
    }

    private var largestFilesSection: some View {
        InsightSection(title: "Largest Files", subtitle: "Top 50 files across the entire selected tree") {
            VStack(spacing: 0) {
                ForEach(insights.largestFiles) { node in
                    FileInsightRow(node: node)
                    if node.id != insights.largestFiles.last?.id { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private var oldLargeFilesSection: some View {
        InsightSection(
            title: "Old Large Files",
            subtitle: "Files larger than 100 MB and unchanged for at least 180 days"
        ) {
            if insights.oldLargeFiles.isEmpty {
                ContentUnavailableView(
                    "No Old Large Files",
                    systemImage: "clock.badge.checkmark",
                    description: Text("No files in this scan match the current criteria."))
            } else {
                VStack(spacing: 0) {
                    ForEach(insights.oldLargeFiles) { node in
                        FileInsightRow(node: node, showsModifiedDate: true)
                        if node.id != insights.oldLargeFiles.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var duplicatesSection: some View {
        InsightSection(
            title: "Duplicate Finder",
            subtitle: "Finds byte-for-byte identical content with SHA-256, not merely equal sizes"
        ) {
            if app.isFindingDuplicates {
                VStack(alignment: .leading, spacing: 10) {
                    if app.duplicateCandidateFiles > 0 {
                        ProgressView(
                            value: Double(app.duplicateFilesHashed),
                            total: Double(app.duplicateCandidateFiles))
                        Text("\(app.duplicateFilesHashed.formatted()) / \(app.duplicateCandidateFiles.formatted()) candidates checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Preparing same-size candidates…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Stop Analysis") { app.cancelDuplicateScan() }
                }
            } else if let groups = app.duplicateGroups {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No Duplicates Found",
                        systemImage: "checkmark.seal.fill",
                        description: Text("No identical content was found among files larger than 1 MB."))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            "\(groups.count.formatted()) groups · up to \(ByteFormat.string(app.duplicateReclaimableBytes)) reclaimable",
                            systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.green)
                        ForEach(groups) { group in
                            DuplicateGroupView(group: group)
                        }
                        Button("Analyze Again") { app.findDuplicates() }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 30))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safe, local duplicate analysis")
                            .font(.headline)
                        Text("Only same-size files larger than 1 MB are hashed. File names and contents never leave this Mac, and nothing is removed automatically.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Find Duplicates") { app.findDuplicates() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ChangeMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StorageChangeRow: View {
    @EnvironmentObject private var app: AppState
    let change: StorageChange

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(change.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(change.kind.title)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 12)
            if change.previousSize > 0, change.currentSize > 0 {
                Text("\(ByteFormat.string(change.previousSize)) → \(ByteFormat.string(change.currentSize))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(deltaText)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
            if let node = change.node {
                Button { app.revealInFinder(node) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 8)
    }

    private var icon: String {
        switch change.kind {
        case .added: return "plus.circle.fill"
        case .grown: return "arrow.up.circle.fill"
        case .shrunk: return "arrow.down.circle.fill"
        case .removed: return "minus.circle.fill"
        }
    }

    private var tint: Color {
        switch change.kind {
        case .added: return .blue
        case .grown: return .orange
        case .shrunk: return .green
        case .removed: return .secondary
        }
    }

    private var deltaText: String {
        if change.delta > 0 { return "+\(ByteFormat.string(change.delta))" }
        return "−\(ByteFormat.string(abs(change.delta)))"
    }
}

private struct InsightSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            content
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct FileInsightRow: View {
    @EnvironmentObject private var app: AppState
    let node: FileNode
    var showsModifiedDate = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: FileCategory.classify(node.url).systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(node.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsModifiedDate, let modifiedAt = node.modifiedAt {
                    Text("Last modified: \(modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(ByteFormat.string(node.size))
                .font(.callout.monospacedDigit().weight(.semibold))
            Button { app.revealInFinder(node) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            Button { app.requestDeletion(of: node) } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Move to Trash after confirmation")
        }
        .padding(.vertical, 8)
    }
}

private struct DuplicateGroupView: View {
    let group: DuplicateGroup

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(group.files) { file in
                    FileInsightRow(node: file)
                    if file.id != group.files.last?.id { Divider() }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange)
                Text("\(group.files.count) identical files")
                    .font(.headline)
                Text("\(ByteFormat.string(group.logicalSize)) each")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Reclaimable: \(ByteFormat.string(group.reclaimableSize))")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
