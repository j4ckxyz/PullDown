import Foundation
import Observation

@Observable
@MainActor
final class PullDownModel {
    let downloadDraft = DownloadDraft()
    private(set) var toolState: ToolState = .checking
    private(set) var ffmpegExecutable: URL?
    private(set) var jobs: [DownloadJob] = []
    private(set) var history: [DownloadHistoryItem] = []
    private(set) var presets: [DownloadPreset] = []
    private(set) var logText = ""
    var errorMessage: String?

    private let ytDLPExecutableLocator: any ExecutableLocating
    private let ffmpegExecutableLocator: any ExecutableLocating
    private let installer: any YTDLPInstalling
    private let processRunner: any ProcessRunning
    private let historyStore: any DownloadHistoryStoring
    private let preferences: AppPreferences
    private let managedBinDirectory: URL
    private var didBootstrap = false
    private var isBootstrapping = false
    private var didLoadHistory = false
    private var currentJobID: UUID?
    private var cancellationRequested = false

    private static let maximumLogLength = 400_000
    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(
        ytDLPExecutableLocator: any ExecutableLocating = ExecutableLocator(),
        ffmpegExecutableLocator: any ExecutableLocating = ExecutableLocator(),
        installer: any YTDLPInstalling = YTDLPInstaller(),
        processRunner: any ProcessRunning = ProcessRunner(),
        historyStore: any DownloadHistoryStoring = DownloadHistoryStore(),
        preferences: AppPreferences = AppPreferences(),
        managedBinDirectory: URL = ExecutableLocator.defaultManagedBinDirectory()
    ) {
        self.ytDLPExecutableLocator = ytDLPExecutableLocator
        self.ffmpegExecutableLocator = ffmpegExecutableLocator
        self.installer = installer
        self.processRunner = processRunner
        self.historyStore = historyStore
        self.preferences = preferences
        self.managedBinDirectory = managedBinDirectory
        loadPresets()
    }

    var isDownloading: Bool { currentJobID != nil }

    var canStartDraftDownload: Bool {
        toolState.isReady
            && isDownloading == false
            && downloadDraft.isLoadingPlaylist == false
            && downloadDraft.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && (downloadDraft.playlistInfo == nil || downloadDraft.selectedPlaylistIndices.isEmpty == false)
    }

    func bootstrap(force: Bool = false) async {
        await loadHistoryIfNeeded()
        guard force || didBootstrap == false else { return }
        // Never probe while a download owns the process runner, and never let
        // overlapping checks (window, menu bar, settings, and the refresh
        // button all call this) collide on it.
        guard isBootstrapping == false, isDownloading == false else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        didBootstrap = true
        toolState = .checking
        ffmpegExecutable = ffmpegExecutableLocator.locate(named: "ffmpeg")
        if let ffmpegExecutable {
            log("Found ffmpeg at \(ffmpegExecutable.path)")
        } else {
            log("ffmpeg not found — merging, audio conversion, and thumbnails may fail.")
        }

        guard let executable = ytDLPExecutableLocator.locate(named: "yt-dlp") else {
            log("yt-dlp not found on this Mac.")
            toolState = .missing
            return
        }
        await verify(executable: executable)
    }

    /// Appends a timestamped line to the persistent app log surfaced in the
    /// Logs tab and the Activity log sheet.
    func log(_ message: String) {
        let stamp = Self.logTimestampFormatter.string(from: Date())
        logText += "[\(stamp)] \(message)\n"
        trimLog()
    }

    func clearLogs() {
        logText = ""
    }

    func exportLogs(to url: URL) throws {
        let contents = logText.isEmpty ? "No activity logged yet.\n" : logText
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func trimLog() {
        if logText.count > Self.maximumLogLength {
            logText = String(logText.suffix(Self.maximumLogLength))
        }
    }

    // MARK: Remembered settings

    /// The last-used options for a tab, falling back to sensible defaults.
    func rememberedOptions(for kind: MediaKind) -> DownloadOptions {
        preferences.rememberedOptions(for: kind) ?? DownloadOptions()
    }

    func rememberOptions(_ options: DownloadOptions, for kind: MediaKind) {
        preferences.setRememberedOptions(options, for: kind)
    }

    // MARK: Presets

    private func loadPresets() {
        var stored = preferences.loadPresets()
        var changed = false

        if preferences.didSeedPresets == false {
            let existingIDs = Set(stored.map(\.id))
            stored.append(contentsOf: DownloadPreset.builtIns.filter { existingIDs.contains($0.id) == false })
            preferences.didSeedPresets = true
            changed = true
        }

        // Backfill icons/colours for built-ins saved before presets had them.
        let builtInsByID = Dictionary(uniqueKeysWithValues: DownloadPreset.builtIns.map { ($0.id, $0) })
        for index in stored.indices {
            guard let builtIn = builtInsByID[stored[index].id], stored[index].isBuiltIn else { continue }
            if stored[index].emoji == nil {
                stored[index].emoji = builtIn.emoji
                changed = true
            }
            if stored[index].tintHex == nil {
                stored[index].tintHex = builtIn.tintHex
                changed = true
            }
        }

        if changed {
            preferences.savePresets(stored)
        }
        presets = stored
    }

    @discardableResult
    func savePreset(
        name: String,
        kind: MediaKind,
        options: DownloadOptions,
        emoji: String? = nil,
        tintHex: String? = nil
    ) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let presetID: UUID
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame && $0.isBuiltIn == false }) {
            presets[index].mediaKind = kind
            presets[index].options = options
            presets[index].emoji = emoji
            presets[index].tintHex = tintHex
            presetID = presets[index].id
        } else {
            let preset = DownloadPreset(name: trimmed, mediaKind: kind, options: options, emoji: emoji, tintHex: tintHex)
            presets.append(preset)
            presetID = preset.id
        }
        persistPresets()
        return presetID
    }

    func renamePreset(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = trimmed
        persistPresets()
    }

    func updatePresetAppearance(id: UUID, emoji: String?, tintHex: String?) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].emoji = emoji
        presets[index].tintHex = tintHex
        persistPresets()
    }

    func updatePreset(id: UUID, name: String, emoji: String?, tintHex: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = trimmed
        presets[index].emoji = emoji
        presets[index].tintHex = tintHex
        persistPresets()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        persistPresets()
    }

    func restoreBuiltInPresets() {
        let existingIDs = Set(presets.map(\.id))
        let missing = DownloadPreset.builtIns.filter { existingIDs.contains($0.id) == false }
        guard missing.isEmpty == false else { return }
        presets.append(contentsOf: missing)
        persistPresets()
    }

    func exportPresets(to url: URL) throws {
        let data = try PresetTransfer.encode(presets)
        try data.write(to: url, options: .atomic)
    }

    /// Imports presets from a file, giving each a fresh identity so imports
    /// never clobber existing presets. Returns the number imported.
    @discardableResult
    func importPresets(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let imported = try PresetTransfer.decode(data)
        guard imported.isEmpty == false else { return 0 }
        for preset in imported {
            presets.append(DownloadPreset(name: preset.name, mediaKind: preset.mediaKind, options: preset.options))
        }
        persistPresets()
        return imported.count
    }

    private func persistPresets() {
        presets.sort { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && rhs.isBuiltIn == false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        preferences.savePresets(presets)
    }

    func installYTDLP() async {
        guard isDownloading == false else { return }
        toolState = .installing
        do {
            let executable = try await installer.install(into: managedBinDirectory)
            await verify(executable: executable)
        } catch is CancellationError {
            toolState = .missing
        } catch {
            toolState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func startDownload(_ request: DownloadRequest) async {
        guard currentJobID == nil else {
            errorMessage = PullDownError.downloadAlreadyRunning.localizedDescription
            return
        }
        guard let executable = toolState.executable else {
            errorMessage = PullDownError.toolUnavailable.localizedDescription
            return
        }

        var job = DownloadJob(request: request)
        job.phase = .downloading
        jobs.insert(job, at: 0)
        currentJobID = job.id
        cancellationRequested = false

        let command = YTDLPCommandBuilder.makeCommand(
            executable: executable,
            request: request,
            ffmpegExecutable: ffmpegExecutable
        )

        log("──────────────────────────────")
        log("Starting \(request.kind.title.lowercased()) download of \(request.urls.count) link(s)")
        log("yt-dlp: \(command.executable.path)")
        log("Command: yt-dlp \(command.arguments.joined(separator: " "))")

        do {
            let stream = try await processRunner.events(for: command)
            for try await event in stream {
                switch event {
                case let .standardOutput(text), let .standardError(text):
                    consume(text, for: job.id)
                }
            }
            if cancellationRequested {
                log("Download cancelled.")
                updateJob(job.id) {
                    $0.phase = .cancelled
                    $0.speed = nil
                    $0.eta = nil
                }
            } else {
                completeJob(job.id)
            }
        } catch is CancellationError {
            log("Download cancelled.")
            updateJob(job.id) {
                $0.phase = .cancelled
                $0.speed = nil
                $0.eta = nil
            }
        } catch {
            if cancellationRequested {
                log("Download cancelled.")
                updateJob(job.id) {
                    $0.phase = .cancelled
                    $0.speed = nil
                    $0.eta = nil
                }
            } else if isPartialPlaylistSuccess(job.id, request: request) {
                // Some playlist items downloaded; only a few were private or
                // unavailable. Treat the batch as complete-with-skips, not failed.
                completeJob(job.id)
            } else {
                log("Download failed: \(error.localizedDescription)")
                updateJob(job.id) {
                    $0.phase = .failed(error.localizedDescription)
                    $0.speed = nil
                    $0.eta = nil
                }
                errorMessage = error.localizedDescription
            }
        }

        await archiveJob(job.id)
        currentJobID = nil
        cancellationRequested = false
    }

    func cancelDownload() async {
        guard let currentJobID else { return }
        cancellationRequested = true
        updateJob(currentJobID) { $0.phase = .cancelled }
        await processRunner.cancel()
    }

    func startDraftDownload(destinationPath: String) async {
        guard canStartDraftDownload else { return }
        do {
            let urls = try YouTubeURLParser.parse(downloadDraft.urlInput)
            downloadDraft.urlInput = urls.map(\.absoluteString).joined(separator: "\n")
            var requestOptions = downloadDraft.options
            if urls.contains(where: YouTubeURLParser.containsPlaylist) {
                requestOptions.downloadPlaylist = true
                if let playlistInfo = downloadDraft.playlistInfo,
                   downloadDraft.selectedPlaylistIndices.count < playlistInfo.videos.count {
                    requestOptions.playlistItems = downloadDraft.selectedPlaylistIndices.sorted()
                }
            }
            let request = DownloadRequest(
                urls: urls,
                kind: downloadDraft.mediaKind,
                destination: URL(fileURLWithPath: destinationPath, isDirectory: true),
                options: requestOptions
            )
            await startDownload(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearHistory() async {
        history.removeAll()
        do {
            try await historyStore.save(history)
        } catch {
            logText += "\nCould not save download history: \(error.localizedDescription)\n"
        }
    }

    func inspectPlaylist(at url: URL) async throws -> PlaylistInfo {
        guard let executable = toolState.executable else {
            throw PullDownError.toolUnavailable
        }
        guard currentJobID == nil else {
            throw PullDownError.downloadAlreadyRunning
        }

        log("Inspecting playlist: \(url.absoluteString)")
        do {
            let json = try await processRunner.capture(executable: executable, arguments: [
                "--ignore-config",
                "--flat-playlist",
                "--dump-single-json",
                "--no-warnings",
                "--yes-playlist",
                url.absoluteString,
            ])
            let info = try YTDLPPlaylistParser.parse(json)
            log("Playlist \"\(info.title)\" loaded with \(info.videos.count) video(s).")
            return info
        } catch {
            log("Playlist inspection failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func verify(executable: URL) async {
        do {
            let version = try await processRunner.capture(executable: executable, arguments: ["--version"])
            guard version.isEmpty == false else {
                throw ProcessExecutionError(exitCode: -1, message: "yt-dlp did not report a version.")
            }
            log("yt-dlp \(version) ready at \(executable.path)")
            toolState = .ready(executable: executable, version: version)
        } catch let error as PullDownError where error == .downloadAlreadyRunning {
            // A download is using the process runner; keep the current state
            // rather than reporting a false failure.
            log("Skipped yt-dlp check — the downloader is busy.")
            if toolState.isReady == false {
                toolState = .ready(executable: executable, version: "in use")
            }
        } catch {
            log("yt-dlp check failed: \(error.localizedDescription)")
            toolState = .failed(error.localizedDescription)
        }
    }

    private func consume(_ text: String, for jobID: UUID) {
        logText += text
        trimLog()

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ERROR:") {
                updateJob(jobID) { $0.failedItemCount += 1 }
            }

            guard let parsed = YTDLPOutputParser.parse(line) else { continue }
            updateJob(jobID) { job in
                if let playlistIndex = parsed.playlistIndex {
                    // A new playlist item started: reset the per-item progress.
                    job.playlistIndex = playlistIndex
                    job.playlistCount = parsed.playlistCount ?? job.playlistCount
                    job.attemptedItemCount += 1
                    job.progress = 0
                    job.speed = nil
                    job.eta = nil
                    job.phase = .downloading
                }
                if let progress = parsed.progress { job.progress = progress }
                if let speed = parsed.speed { job.speed = speed }
                if let eta = parsed.eta { job.eta = eta }
                if let outputPath = parsed.outputPath { job.outputPath = outputPath }
                if parsed.isPostProcessing {
                    job.phase = .processing
                    job.speed = nil
                    job.eta = nil
                } else if parsed.progress == 1 {
                    job.speed = nil
                    job.eta = nil
                }
            }
        }
    }

    private func loadHistoryIfNeeded() async {
        guard didLoadHistory == false else { return }
        didLoadHistory = true
        do {
            history = try await historyStore.load()
                .sorted { $0.finishedAt > $1.finishedAt }
        } catch {
            logText += "Could not load download history: \(error.localizedDescription)\n"
        }
    }

    private func archiveJob(_ id: UUID) async {
        guard
            let job = jobs.first(where: { $0.id == id }),
            let item = DownloadHistoryItem(job: job)
        else { return }

        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        if history.count > 200 {
            history.removeLast(history.count - 200)
        }
        do {
            try await historyStore.save(history)
        } catch {
            logText += "\nCould not save download history: \(error.localizedDescription)\n"
        }
    }

    private func updateJob(_ id: UUID, update: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        update(&jobs[index])
    }

    private func completeJob(_ id: UUID) {
        let summary = jobs.first(where: { $0.id == id })?.completionSummary
        if let summary {
            log("Download completed. \(summary).")
        } else {
            log("Download completed.")
        }
        updateJob(id) {
            $0.phase = .completed
            $0.progress = 1
            $0.speed = nil
            $0.eta = nil
        }
    }

    /// True when a playlist download exited non-zero but at least one item was
    /// actually downloaded (the rest being private or unavailable).
    private func isPartialPlaylistSuccess(_ id: UUID, request: DownloadRequest) -> Bool {
        let isPlaylist = request.options.downloadPlaylist
            || (request.options.playlistItems?.isEmpty == false)
        guard isPlaylist, let job = jobs.first(where: { $0.id == id }) else { return false }
        let total = job.playlistCount ?? job.attemptedItemCount
        let succeeded = total - job.failedItemCount
        return succeeded > 0 && job.failedItemCount > 0
    }
}
