import SwiftUI

// MARK: - Top toolbar

struct TopBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 12) {
            Button {
                app.chooseAndScan()
            } label: {
                Label("Qovluq Seç", systemImage: "folder")
            }

            if app.scanRootURL != nil {
                Button {
                    app.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Yenidən tara")

                Button {
                    app.goUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(app.focus?.parent == nil)
                .help("Bir səviyyə yuxarı")
            }

            if let focus = app.focus {
                Breadcrumb(focus: focus) { app.setFocus($0) }
            }

            Spacer(minLength: 12)

            Picker("", selection: $app.mode) {
                ForEach(AppState.ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(app.focus == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Breadcrumb

private struct Breadcrumb: View {
    let focus: FileNode
    let onSelect: (FileNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let chain = focus.ancestryFromRoot
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        onSelect(node)
                    } label: {
                        Text(node.displayName)
                            .lineLimit(1)
                            .font(.callout)
                            .fontWeight(node.id == focus.id ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(node.id == focus.id ? Color.primary : Color.accentColor)
                }
            }
        }
        .frame(maxWidth: 440)
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
            Text("Offline · silmə yalnız təsdiqlə · App Sandbox")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if let hovered = app.hovered {
                Text(hovered.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteFormat.string(hovered.size))
                    .font(.caption.weight(.semibold))
            } else if let root = app.root {
                Text("\(app.totalItems) element")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Cəmi: \(ByteFormat.string(root.size))")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Scanning state

struct ScanningView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Taranır…")
                .font(.title3.weight(.semibold))
            Text("\(app.scannedFiles) element · \(ByteFormat.string(app.scannedBytes))")
                .foregroundStyle(.secondary)
            Text(app.currentScanPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
            Button("Ləğv et") { app.cancelScan() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 18) {
            FlareScanLogo(size: 92)
            Text("Flare Scan")
                .font(.largeTitle.bold())
            Text("Diskinizin hansı qovluq və fayllarla dolduğunu\ngörün — tam detallı, interaktiv analiz.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                app.chooseAndScan()
            } label: {
                Label("Qovluq və ya Disk Seç", systemImage: "folder")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Tam offline · silmə yalnız təsdiqlə · şəbəkəyə çıxış yoxdur")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FlareScanLogo: View {
    let size: CGFloat

    var body: some View {
        if let url = logoURL,
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("Flare Scan loqosu")
        } else {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: size * 0.65))
                .foregroundStyle(.tint)
        }
    }

    private var logoURL: URL? {
        Bundle.main.url(forResource: "FlareScan", withExtension: "svg")
            ?? Bundle.module.url(forResource: "FlareScan", withExtension: "svg")
    }
}
