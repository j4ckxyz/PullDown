import AppKit
import SwiftUI

struct ActivityView: View {
    @Environment(PullDownModel.self) private var model
    @State private var showsLog = false

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                EmptyActivityView()
            } else {
                List(model.jobs) { job in
                    DownloadJobRow(job: job)
                        .contextMenu {
                            Button("Open destination") {
                                NSWorkspace.shared.open(job.request.destination)
                            }
                            if let outputPath = job.outputPath {
                                Button("Reveal downloaded file") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
                                }
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Show Log") { showsLog = true }
                    .disabled(model.logText.isEmpty)
            }
        }
        .sheet(isPresented: $showsLog) {
            DownloadLogView(logText: model.logText)
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

            if job.phase == .downloading || job.phase == .processing {
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
