import AppKit
import SwiftUI

struct DownloadView: View {
    @Environment(PullDownModel.self) private var model
    @AppStorage(AppPreferenceKeys.destinationPath) private var destinationPath = AppDefaults.downloadsDirectory.path
    @AppStorage(AppPreferenceKeys.defaultMediaKind) private var defaultMediaKind = MediaKind.video.rawValue

    @State private var urlInput = ""
    @State private var mediaKind: MediaKind = .video
    @State private var options = DownloadOptions()
    @State private var showsAdvanced = false
    @State private var playlistInfo: PlaylistInfo?
    @State private var selectedPlaylistIndices = Set<Int>()
    @State private var loadedPlaylistURL: URL?
    @State private var isLoadingPlaylist = false
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if model.toolState.isReady == false {
                    dependencyCard
                }
                downloadCard
                recentActivity
            }
            .padding(16)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            mediaKind = MediaKind(rawValue: defaultMediaKind) ?? .video
            urlFieldFocused = isScreenshotMode == false
#if DEBUG
            if ProcessInfo.processInfo.environment["PULLDOWN_SCREENSHOT"] == "1" {
                urlInput = "https://www.youtube.com/watch?v=xVQrqAxdH9w&list=PLgvFSQ2xChFMcBRbCGOkNMbKxm0oJ2z3H"
                let names = [
                    1: "A Kind of Magic",
                    2: "A Winter's Tale",
                    3: "Bicycle Race",
                    4: "Brighton Rock",
                    5: "Another One Bites the Dust",
                ]
                let videos = (1...89).map { index in
                    PlaylistVideo(
                        index: index,
                        videoID: "preview-\(index)",
                        title: names[index] ?? "Queen instrumental track \(index)",
                        duration: Double(170 + index)
                    )
                }
                playlistInfo = PlaylistInfo(title: "Queen instrumental", videos: videos)
                selectedPlaylistIndices = Set(videos.map(\.index))
                loadedPlaylistURL = detectedPlaylistURL
            }
#endif
        }
        .onChange(of: urlInput) { _, _ in
            guard loadedPlaylistURL != detectedPlaylistURL else { return }
            playlistInfo = nil
            selectedPlaylistIndices.removeAll()
            loadedPlaylistURL = nil
        }
    }

    private var header: some View {
        Text("New download")
            .font(.title2.weight(.semibold))
    }

    private var dependencyCard: some View {
        HStack(spacing: 14) {
            ToolStatusView(state: model.toolState)
            Spacer()
            if model.toolState == .missing || isFailure {
                Button("Install verified release") {
                    Task { await model.installYTDLP() }
                }
                .pullDownPrimaryButtonStyle()
            } else if model.toolState == .installing || model.toolState == .checking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking yt-dlp")
            }
        }
        .pullDownCard(cornerRadius: 16, padding: 16)
    }

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("YouTube links", systemImage: "link")
                        .font(.headline)
                    Spacer()
                    Button("Paste") { pasteURL() }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                }

                TextEditor(text: $urlInput)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 58, maxHeight: 76)
                    .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.separator, lineWidth: 1)
                    }
                    .focused($urlFieldFocused)
                    .accessibilityLabel("YouTube URLs")
                    .accessibilityHint("Enter one or more YouTube links separated by spaces or new lines.")
                    .accessibilityIdentifier("urlEditor")
            }

            Picker("Download as", selection: $mediaKind) {
                ForEach(MediaKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mediaKindPicker")

            qualityControls
            playlistControls
            destinationRow

            DisclosureGroup("Advanced options", isExpanded: $showsAdvanced) {
                advancedOptions
                    .padding(.top, 12)
            }

            HStack {
                if model.ffmpegExecutable == nil, needsFFmpeg {
                    Label("FFmpeg is recommended for conversion and merging", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isDownloading {
                    Button("Cancel", role: .cancel) {
                        Task { await model.cancelDownload() }
                    }
                }
                Button(model.isDownloading ? "Downloading…" : "Download") {
                    startDownload()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(canDownload == false)
                .pullDownPrimaryButtonStyle()
                .accessibilityIdentifier("downloadButton")
            }
        }
        .pullDownCard(cornerRadius: 16, padding: 16)
    }

    @ViewBuilder
    private var qualityControls: some View {
        HStack(alignment: .top, spacing: 16) {
            if mediaKind == .video {
                Picker("Quality", selection: $options.videoQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                Picker("Container", selection: $options.videoContainer) {
                    ForEach(VideoContainer.allCases) { container in
                        Text(container.title).tag(container)
                    }
                }
            } else {
                Picker("Format", selection: $options.audioFormat) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Picker("Quality", selection: $options.audioQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            }
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Save to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(destinationPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Choose…", action: chooseDestination)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var playlistControls: some View {
        if let playlistURL = detectedPlaylistURL {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Playlist detected", systemImage: "rectangle.stack.fill")
                        .font(.headline)
                    Spacer()
                    if isLoadingPlaylist {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading playlist videos")
                    } else {
                        Button(playlistInfo == nil ? "Choose videos…" : "Reload playlist") {
                            loadPlaylist(playlistURL)
                        }
                    }
                }

                if let playlistInfo {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlistInfo.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(selectedPlaylistIndices.count) of \(playlistInfo.videos.count) videos selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Select all") {
                            selectedPlaylistIndices = Set(playlistInfo.videos.map(\.index))
                        }
                        Button("Select none") {
                            selectedPlaylistIndices.removeAll()
                        }
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(playlistInfo.videos) { video in
                                    Toggle(isOn: playlistBinding(for: video.index)) {
                                        HStack(spacing: 10) {
                                            Text("\(video.index)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .frame(width: 30, alignment: .trailing)
                                            Text(video.title)
                                                .lineLimit(1)
                                            Spacer()
                                            if let duration = video.durationText {
                                                Text(duration)
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .id(video.index)
                                }
                            }
                        }
                        .defaultScrollAnchor(.top)
                        .onAppear {
                            if let firstIndex = playlistInfo.videos.first?.index {
                                proxy.scrollTo(firstIndex, anchor: .top)
                            }
                        }
                    }
                    .frame(maxHeight: 170)
                } else {
                    Text("Download the whole playlist now, or load its contents to choose individual videos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var advancedOptions: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                Toggle("Download playlists", isOn: $options.downloadPlaylist)
                Toggle("Embed metadata", isOn: $options.embedMetadata)
            }
            GridRow {
                Toggle("Embed thumbnail", isOn: $options.embedThumbnail)
                Toggle("Include subtitles", isOn: $options.includeSubtitles)
                    .disabled(mediaKind == .audio)
            }
            GridRow {
                Stepper("Concurrent fragments: \(options.concurrentFragments)", value: $options.concurrentFragments, in: 1...16)
                    .gridCellColumns(2)
            }
            GridRow {
                TextField("Filename template", text: $options.filenameTemplate)
                    .textFieldStyle(.roundedBorder)
                    .gridCellColumns(2)
                    .accessibilityHint("Uses yt-dlp output template syntax.")
            }
        }
    }

    @ViewBuilder
    private var recentActivity: some View {
        if let job = model.jobs.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Latest activity")
                        .font(.headline)
                    Spacer()
                    Text(job.phase.title)
                        .foregroundStyle(.secondary)
                }
                DownloadJobRow(job: job)
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = model.toolState { true } else { false }
    }

    private var needsFFmpeg: Bool {
        mediaKind == .audio || options.videoQuality != .best || options.videoContainer != .automatic
    }

    private var canDownload: Bool {
        model.toolState.isReady
            && model.isDownloading == false
            && urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && (playlistInfo == nil || selectedPlaylistIndices.isEmpty == false)
            && isScreenshotMode == false
    }

    private var isScreenshotMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["PULLDOWN_SCREENSHOT"] == "1"
#else
        false
#endif
    }

    private var detectedPlaylistURL: URL? {
        guard let urls = try? YouTubeURLParser.parse(urlInput) else { return nil }
        return urls.first(where: YouTubeURLParser.containsPlaylist)
    }

    private func pasteURL() {
        guard let value = NSPasteboard.general.string(forType: .string), value.isEmpty == false else { return }
        if let urls = try? YouTubeURLParser.parse(value) {
            urlInput = urls.map(\.absoluteString).joined(separator: "\n")
        } else {
            urlInput = value
        }
        urlFieldFocused = true
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose a download folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationPath = url.path
    }

    private func startDownload() {
        guard isScreenshotMode == false else { return }
        do {
            let urls = try YouTubeURLParser.parse(urlInput)
            urlInput = urls.map(\.absoluteString).joined(separator: "\n")
            var requestOptions = options
            if urls.contains(where: YouTubeURLParser.containsPlaylist) {
                requestOptions.downloadPlaylist = true
                if let playlistInfo, selectedPlaylistIndices.count < playlistInfo.videos.count {
                    requestOptions.playlistItems = selectedPlaylistIndices.sorted()
                }
            }
            let request = DownloadRequest(
                urls: urls,
                kind: mediaKind,
                destination: URL(fileURLWithPath: destinationPath, isDirectory: true),
                options: requestOptions
            )
            Task { await model.startDownload(request) }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func loadPlaylist(_ url: URL) {
        isLoadingPlaylist = true
        Task {
            do {
                let info = try await model.inspectPlaylist(at: url)
                playlistInfo = info
                selectedPlaylistIndices = Set(info.videos.map(\.index))
                loadedPlaylistURL = url
            } catch {
                model.errorMessage = error.localizedDescription
            }
            isLoadingPlaylist = false
        }
    }

    private func playlistBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { selectedPlaylistIndices.contains(index) },
            set: { isSelected in
                if isSelected {
                    selectedPlaylistIndices.insert(index)
                } else {
                    selectedPlaylistIndices.remove(index)
                }
            }
        )
    }
}
