import AppKit
import SwiftUI

struct MenuBarDownloadView: View {
    @Environment(PullDownModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppPreferenceKeys.destinationPath) private var destinationPath = AppDefaults.downloadsDirectory.path
    @AppStorage(AppPreferenceKeys.defaultMediaKind) private var defaultMediaKind = MediaKind.video.rawValue

    @State private var urlInput = ""
    @State private var mediaKind: MediaKind = .video
    @State private var videoQuality: VideoQuality = .fullHD
    @State private var audioFormat: AudioFormat = .m4a

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("PullDown", systemImage: "arrow.down.circle.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                ToolStatusView(state: model.toolState, compact: true)
            }

            if model.toolState.isReady {
                HStack(spacing: 8) {
                    TextField("Paste a YouTube URL", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(startDownload)
                        .accessibilityIdentifier("menuBarURLField")
                    Button(action: pasteURL) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .accessibilityLabel("Paste YouTube URL") // [VERIFY] confirm label matches intent
                    .accessibilityInputLabels(["Paste YouTube URL", "Paste"])
                }

                Picker("Download as", selection: $mediaKind) {
                    ForEach(MediaKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if mediaKind == .video {
                    Picker("Quality", selection: $videoQuality) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                } else {
                    Picker("Format", selection: $audioFormat) {
                        ForEach(AudioFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                }

                if let job = model.jobs.first, model.isDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: job.progress)
                        HStack {
                            Text(job.phase.title)
                            Spacer()
                            Text(job.progress.formatted(.percent.precision(.fractionLength(0))))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if model.isDownloading {
                        Button("Cancel", role: .cancel) {
                            Task { await model.cancelDownload() }
                        }
                    }
                    Spacer()
                    Button(model.isDownloading ? "Downloading…" : "Download", action: startDownload)
                        .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isDownloading)
                        .pullDownPrimaryButtonStyle()
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PullDown needs yt-dlp before it can download anything.")
                        .foregroundStyle(.secondary)
                    Button("Install verified release") {
                        Task { await model.installYTDLP() }
                    }
                    .disabled(model.toolState == .installing || model.toolState == .checking)
                    .pullDownPrimaryButtonStyle()
                }
                .pullDownCard(cornerRadius: 14, padding: 14)
            }

            Divider()

            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Open PullDown") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: 370)
        .onAppear { mediaKind = MediaKind(rawValue: defaultMediaKind) ?? .video }
    }

    private func pasteURL() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        if let urls = try? YouTubeURLParser.parse(value) {
            urlInput = urls.map(\.absoluteString).joined(separator: " ")
        } else {
            urlInput = value
        }
    }

    private func startDownload() {
        do {
            let urls = try YouTubeURLParser.parse(urlInput)
            urlInput = urls.map(\.absoluteString).joined(separator: " ")
            var options = DownloadOptions()
            options.videoQuality = videoQuality
            options.audioFormat = audioFormat
            options.downloadPlaylist = urls.contains(where: YouTubeURLParser.containsPlaylist)
            let request = DownloadRequest(
                urls: urls,
                kind: mediaKind,
                destination: URL(fileURLWithPath: destinationPath, isDirectory: true),
                options: options
            )
            Task { await model.startDownload(request) }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
