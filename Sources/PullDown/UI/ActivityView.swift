import AppKit
import SwiftUI

struct ActivityView: View {
    @Environment(PullDownModel.self) private var model
    @State private var showsLog = false
    @State private var confirmsClearHistory = false

    var body: some View {
        Group {
            if activeJobs.isEmpty && model.history.isEmpty {
                EmptyActivityView()
            } else {
                List {
                    if activeJobs.isEmpty == false {
                        Section("Current") {
                            ForEach(activeJobs) { job in
                                DownloadJobRow(job: job)
                                    .contextMenu {
                                        Button("Open destination") {
                                            NSWorkspace.shared.open(job.request.destination)
                                        }
                                    }
                            }
                        }
                    }

                    if model.history.isEmpty == false {
                        Section("Recent downloads") {
                            ForEach(model.history) { item in
                                DownloadHistoryRow(item: item) {
                                    Task { await model.startDownload(item.request) }
                                }
                                .contextMenu {
                                    historyActions(for: item)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Clear History") { confirmsClearHistory = true }
                    .disabled(model.history.isEmpty)
                Button("Show Log") { showsLog = true }
                    .disabled(model.logText.isEmpty)
            }
        }
        .sheet(isPresented: $showsLog) {
            DownloadLogView(logText: model.logText)
        }
        .confirmationDialog(
            "Clear download history?",
            isPresented: $confirmsClearHistory
        ) {
            Button("Clear History", role: .destructive) {
                Task { await model.clearHistory() }
            }
        } message: {
            Text("Downloaded files will not be removed.")
        }
    }

    private var activeJobs: [DownloadJob] {
        model.jobs.filter {
            switch $0.phase {
            case .queued, .downloading, .processing: true
            case .completed, .cancelled, .failed: false
            }
        }
    }

    @ViewBuilder
    private func historyActions(for item: DownloadHistoryItem) -> some View {
        if let outputURL = item.outputURL {
            Button("Reveal downloaded file") {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
        }
        Button("Open destination") {
            NSWorkspace.shared.open(item.destinationURL)
        }
        Button("Copy source URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                item.request.urls.map(\.absoluteString).joined(separator: "\n"),
                forType: .string
            )
        }
        Divider()
        Button("Download again") {
            Task { await model.startDownload(item.request) }
        }
        .disabled(model.isDownloading || model.toolState.isReady == false)
    }
}

private struct DownloadHistoryRow: View {
    @Environment(PullDownModel.self) private var model
    let item: DownloadHistoryItem
    let downloadAgain: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColour)
                .font(.title3)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.request.kind.title)
                    Text("·")
                    Text(item.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(item.status.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let failureMessage = item.failureMessage {
                    Text(failureMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else {
                    Text(item.outputPath ?? item.request.destination.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Menu {
                if let outputURL = item.outputURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                }
                Button("Open destination") {
                    NSWorkspace.shared.open(item.destinationURL)
                }
                Divider()
                Button("Download again", action: downloadAgain)
                    .disabled(model.isDownloading || model.toolState.isReady == false)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(item.displayName)")
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private var statusSymbol: String {
        switch item.status {
        case .completed: "checkmark.circle.fill"
        case .cancelled: "stop.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColour: Color {
        switch item.status {
        case .completed: .green
        case .cancelled: .secondary
        case .failed: .red
        }
    }
}

struct DownloadJobRow: View {
    let job: DownloadJob

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(job.request.kind.title, systemImage: phaseSymbol)
                    .font(.headline)
                    .foregroundStyle(phaseColor)
                Text("· \(job.request.urls.count) \(job.request.urls.count == 1 ? "link" : "links")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(job.phase.title)
                    .font(.subheadline.weight(.medium))
            }

            if job.phase == .downloading {
                ProgressView(value: job.progress)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue(job.progress.formatted(.percent.precision(.fractionLength(0))))
                HStack {
                    if let speed = job.speed { Text(speed) }
                    Spacer()
                    if let eta = job.eta { Text("ETA \(eta)") }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if job.phase == .processing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Finalising downloaded file")
                Text("Finalising file…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = job.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let outputPath = job.outputPath {
                Text(outputPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(job.request.destination.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var phaseSymbol: String {
        switch job.phase {
        case .queued: "clock"
        case .downloading: "arrow.down.circle.fill"
        case .processing: "wand.and.stars"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "stop.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var phaseColor: Color {
        switch job.phase {
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        case .queued: .secondary
        case .downloading, .processing: .accentColor
        }
    }
}

private struct DownloadLogView: View {
    @Environment(\.dismiss) private var dismiss
    let logText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("yt-dlp Log")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 420)
    }
}
