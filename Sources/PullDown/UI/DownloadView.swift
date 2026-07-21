import AppKit
import SwiftUI

struct DownloadView: View {
    @Environment(PullDownModel.self) private var model
    @AppStorage(AppPreferenceKeys.destinationPath) private var destinationPath = AppDefaults.downloadsDirectory.path
    @AppStorage(AppPreferenceKeys.defaultMediaKind) private var defaultMediaKind = MediaKind.video.rawValue

    @Bindable var draft: DownloadDraft
    @FocusState private var urlFieldFocused: Bool
    @State private var isSavingPreset = false

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
        .background(.clear)
        .onAppear {
            if draft.didLoadPreferences == false {
                draft.mediaKind = MediaKind(rawValue: defaultMediaKind) ?? .video
                draft.options = model.rememberedOptions(for: draft.mediaKind)
                draft.didLoadPreferences = true
            }
            urlFieldFocused = true
        }
        .onChange(of: draft.urlInput) { _, _ in
            guard draft.loadedPlaylistURL != detectedPlaylistURL else { return }
            draft.playlistInfo = nil
            draft.selectedPlaylistIndices.removeAll()
            draft.loadedPlaylistURL = nil
        }
        .onChange(of: draft.options) { _, newValue in
            guard draft.didLoadPreferences else { return }
            model.rememberOptions(newValue, for: draft.mediaKind)
        }
        .sheet(isPresented: $isSavingPreset) {
            PresetEditorSheet(
                title: "Save preset",
                mediaKind: draft.mediaKind,
                name: activePreset?.name ?? "",
                emoji: activePreset?.displayEmoji ?? "",
                tintHex: activePreset?.tintHex
            ) { name, emoji, tintHex in
                model.savePreset(
                    name: name,
                    kind: draft.mediaKind,
                    options: draft.options,
                    emoji: emoji,
                    tintHex: tintHex
                )
            }
        }
    }

    private var mediaKindBinding: Binding<MediaKind> {
        Binding(
            get: { draft.mediaKind },
            set: { newKind in
                guard newKind != draft.mediaKind else { return }
                model.rememberOptions(draft.options, for: draft.mediaKind)
                draft.mediaKind = newKind
                draft.options = model.rememberedOptions(for: newKind)
                defaultMediaKind = newKind.rawValue
            }
        )
    }

    private func applyPreset(_ preset: DownloadPreset) {
        model.rememberOptions(draft.options, for: draft.mediaKind)
        draft.mediaKind = preset.mediaKind
        draft.options = preset.options
        defaultMediaKind = preset.mediaKind.rawValue
        model.rememberOptions(preset.options, for: preset.mediaKind)
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

                TextEditor(text: $draft.urlInput)
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

            Picker("Download as", selection: mediaKindBinding) {
                ForEach(MediaKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mediaKindPicker")

            presetsBar
            playlistControls
            destinationRow

            DisclosureGroup("Format & advanced options", isExpanded: $draft.showsAdvanced) {
                VStack(alignment: .leading, spacing: 14) {
                    qualityControls
                    advancedOptions
                }
                .padding(.top, 12)
            }

            HStack {
                Button {
                    isSavingPreset = true
                } label: {
                    Label("Save as preset…", systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("savePresetButton")

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
                .disabled(canDownload == false)
                .pullDownPrimaryButtonStyle()
                .accessibilityIdentifier("downloadButton")
            }
        }
        .pullDownCard(cornerRadius: 16, padding: 16)
    }

    /// Presets that apply to the currently selected tab.
    private var presetsForCurrentKind: [DownloadPreset] {
        model.presets.filter { $0.mediaKind == draft.mediaKind }
    }

    /// The preset whose options exactly match the current configuration, if any.
    private var activePreset: DownloadPreset? {
        presetsForCurrentKind.first { $0.options == draft.options }
    }

    private var presetButtonTitle: String {
        if let activePreset {
            return "\(activePreset.displayEmoji) \(activePreset.name)"
        }
        return "Custom settings"
    }

    private var presetsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Menu {
                    if presetsForCurrentKind.isEmpty {
                        Text("No \(draft.mediaKind.title.lowercased()) presets yet")
                    } else {
                        ForEach(presetsForCurrentKind) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                let marker = preset.id == activePreset?.id ? "  ✓" : ""
                                Text("\(preset.displayEmoji)  \(preset.name)\(marker)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text(presetButtonTitle)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityIdentifier("presetsMenu")

                Spacer()
            }

            Text("Presets fill in the format options below — you can still tweak anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var qualityControls: some View {
        HStack(alignment: .top, spacing: 16) {
            if draft.mediaKind == .video {
                Picker("Quality", selection: $draft.options.videoQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                Picker("Container", selection: $draft.options.videoContainer) {
                    ForEach(VideoContainer.allCases) { container in
                        Text(container.title).tag(container)
                    }
                }
            } else {
                Picker("Format", selection: $draft.options.audioFormat) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Picker("Quality", selection: $draft.options.audioQuality) {
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
                    if draft.isLoadingPlaylist {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading playlist videos")
                    } else {
                        Button(draft.playlistInfo == nil ? "Choose videos…" : "Reload playlist") {
                            loadPlaylist(playlistURL)
                        }
                        .disabled(model.isDownloading)
                    }
                }

                if let playlistInfo = draft.playlistInfo {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlistInfo.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(draft.selectedPlaylistIndices.count) of \(playlistInfo.videos.count) videos selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Select all") {
                            draft.selectedPlaylistIndices = Set(playlistInfo.videos.map(\.index))
                        }
                        Button("Select none") {
                            draft.selectedPlaylistIndices.removeAll()
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
                Toggle("Download playlists", isOn: $draft.options.downloadPlaylist)
                Toggle("Embed metadata", isOn: $draft.options.embedMetadata)
            }
            GridRow {
                Toggle("Embed thumbnail", isOn: $draft.options.embedThumbnail)
                Toggle("Include subtitles", isOn: $draft.options.includeSubtitles)
                    .disabled(draft.mediaKind == .audio)
            }
            GridRow {
                Stepper("Concurrent fragments: \(draft.options.concurrentFragments)", value: $draft.options.concurrentFragments, in: 1...16)
                    .gridCellColumns(2)
            }
            GridRow {
                TextField("Filename template", text: $draft.options.filenameTemplate)
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
        draft.mediaKind == .audio || draft.options.videoQuality != .best || draft.options.videoContainer != .automatic
    }

    private var canDownload: Bool {
        model.canStartDraftDownload
    }

    private var detectedPlaylistURL: URL? {
        guard let urls = try? YouTubeURLParser.parse(draft.urlInput) else { return nil }
        return urls.first(where: YouTubeURLParser.containsPlaylist)
    }

    private func pasteURL() {
        guard let value = NSPasteboard.general.string(forType: .string), value.isEmpty == false else { return }
        if let urls = try? YouTubeURLParser.parse(value) {
            draft.urlInput = urls.map(\.absoluteString).joined(separator: "\n")
        } else {
            draft.urlInput = value
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
        Task { await model.startDraftDownload(destinationPath: destinationPath) }
    }

    private func loadPlaylist(_ url: URL) {
        guard model.isDownloading == false else { return }
        draft.isLoadingPlaylist = true
        Task {
            do {
                let info = try await model.inspectPlaylist(at: url)
                draft.playlistInfo = info
                draft.selectedPlaylistIndices = Set(info.videos.map(\.index))
                draft.loadedPlaylistURL = url
            } catch {
                model.errorMessage = error.localizedDescription
            }
            draft.isLoadingPlaylist = false
        }
    }

    private func playlistBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { draft.selectedPlaylistIndices.contains(index) },
            set: { isSelected in
                if isSelected {
                    draft.selectedPlaylistIndices.insert(index)
                } else {
                    draft.selectedPlaylistIndices.remove(index)
                }
            }
        )
    }
}
