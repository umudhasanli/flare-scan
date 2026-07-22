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
                Text("Ən çox yer tutan faylları, kateqoriyaları və eyni məzmunlu nüsxələri bir yerdə görün.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.isExportingReport {
                ProgressView()
                    .controlSize(.small)
                Text("Hesabat hazırlanır…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if app.lastExportURL != nil {
                Button("Hesabatı Finder-də göstər") { app.revealLastExport() }
            }
            Menu {
                Button("JSON hesabat") { app.exportInsights(as: .json) }
                Button("CSV hesabat") { app.exportInsights(as: .csv) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(app.isExportingReport)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            MetricCard(
                title: "İstifadə olunan yer",
                value: ByteFormat.string(app.root?.size ?? 0),
                icon: "internaldrive.fill",
                tint: .blue)
            MetricCard(
                title: "Fayllar",
                value: insights.fileCount.formatted(),
                icon: "doc.on.doc",
                tint: .indigo)
            MetricCard(
                title: "Qovluqlar",
                value: insights.directoryCount.formatted(),
                icon: "folder.fill",
                tint: .orange)
            MetricCard(
                title: "Duplicate qənaəti",
                value: app.duplicateGroups == nil ? "Hələ yoxlanmayıb" : ByteFormat.string(app.duplicateReclaimableBytes),
                icon: "square.on.square",
                tint: .green)
        }
    }

    @ViewBuilder
    private var scanQualitySection: some View {
        if app.scanIssueCount == 0 {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                Text("Scan tamamlandı — oxuna bilməyən element qeydə alınmadı.")
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
                        Text("Daha \((app.scanIssueCount - app.scanIssues.count).formatted()) xəta hesabatda say olaraq saxlanılıb.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(
                    "\(app.scanIssueCount.formatted()) element oxunmadı — nəticə natamam ola bilər",
                    systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var categorySection: some View {
        InsightSection(title: "Kateqoriyalar", subtitle: "Fayl tiplərinin diskdə tutduğu real yer") {
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
                        Text("\(item.fileCount.formatted()) fayl")
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

    private var largestFilesSection: some View {
        InsightSection(title: "Ən böyük fayllar", subtitle: "Bütün seçilmiş ağac üzrə ilk 50 fayl") {
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
            title: "Köhnə böyük fayllar",
            subtitle: "100 MB-dan böyük və ən az 180 gündür dəyişdirilməyən fayllar"
        ) {
            if insights.oldLargeFiles.isEmpty {
                ContentUnavailableView(
                    "Köhnə böyük fayl tapılmadı",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Bu scan-da göstərilən meyarlara uyğun fayl yoxdur."))
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
            subtitle: "Eyni ölçünü yox, SHA-256 ilə byte-for-byte eyni məzmunu tapır"
        ) {
            if app.isFindingDuplicates {
                VStack(alignment: .leading, spacing: 10) {
                    if app.duplicateCandidateFiles > 0 {
                        ProgressView(
                            value: Double(app.duplicateFilesHashed),
                            total: Double(app.duplicateCandidateFiles))
                        Text("\(app.duplicateFilesHashed.formatted()) / \(app.duplicateCandidateFiles.formatted()) namizəd yoxlanıb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Eyni ölçülü namizədlər hazırlanır…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Yoxlamanı dayandır") { app.cancelDuplicateScan() }
                }
            } else if let groups = app.duplicateGroups {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "Duplicate tapılmadı",
                        systemImage: "checkmark.seal.fill",
                        description: Text("1 MB-dan böyük fayllar arasında eyni məzmunlu nüsxə yoxdur."))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            "\(groups.count.formatted()) qrup · potensial \(ByteFormat.string(app.duplicateReclaimableBytes)) qənaət",
                            systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.green)
                        ForEach(groups) { group in
                            DuplicateGroupView(group: group)
                        }
                        Button("Yenidən yoxla") { app.findDuplicates() }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 30))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Təhlükəsiz, lokal duplicate analizi")
                            .font(.headline)
                        Text("Yalnız 1 MB-dan böyük, eyni ölçülü fayllar hash edilir. Fayl adları və məzmun cihazdan çıxmır; heç nə avtomatik silinmir.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Duplicate-ləri tap") { app.findDuplicates() }
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
                    Text("Son dəyişiklik: \(modifiedAt.formatted(date: .abbreviated, time: .omitted))")
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
            .help("Finder-də göstər")
            Button { app.requestDeletion(of: node) } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Təsdiqdən sonra Zibil qutusuna köçür")
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
                Text("\(group.files.count) eyni fayl")
                    .font(.headline)
                Text("hər biri \(ByteFormat.string(group.logicalSize))")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Qənaət: \(ByteFormat.string(group.reclaimableSize))")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
