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
    private(set) var logText = ""
    var errorMessage: String?

    private let ytDLPExecutableLocator: any ExecutableLocating
    private let ffmpegExecutableLocator: any ExecutableLocating
    private let installer: any YTDLPInstalling
    private let processRunner: any ProcessRunning
    private let historyStore: any DownloadHistoryStoring
    private let managedBinDirectory: URL
    private var didBootstrap = false
    private var didLoadHistory = false
    private var currentJobID: UUID?
    private var cancellationRequested = false

    init(
        ytDLPExecutableLocator: any ExecutableLocating = ExecutableLocator(),
        ffmpegExecutableLocator: any ExecutableLocating = ExecutableLocator(),
        installer: any YTDLPInstalling = YTDLPInstaller(),
        processRunner: any ProcessRunning = ProcessRunner(),
        historyStore: any DownloadHistoryStoring = DownloadHistoryStore(),
        managedBinDirectory: URL = ExecutableLocator.defaultManagedBinDirectory()
    ) {
        self.ytDLPExecutableLocator = ytDLPExecutableLocator
        self.ffmpegExecutableLocator = ffmpegExecutableLocator
        self.installer = installer
        self.processRunner = processRunner
        self.historyStore = historyStore
        self.managedBinDirectory = managedBinDirectory
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
        didBootstrap = true
        toolState = .checking
        ffmpegExecutable = ffmpegExecutableLocator.locate(named: "ffmpeg")

        guard let executable = ytDLPExecutableLocator.locate(named: "yt-dlp") else {
            toolState = .missing
            return
        }
        await verify(executable: executable)
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
        logText = ""

        let command = YTDLPCommandBuilder.makeCommand(
            executable: executable,
            request: request,
            ffmpegExecutable: ffmpegExecutable
        )

        do {
            let stream = try await processRunner.events(for: command)
            for try await event in stream {
                switch event {
                case let .standardOutput(text), let .standardError(text):
                    consume(text, for: job.id)
                }
            }
            if cancellationRequested {
                updateJob(job.id) {
                    $0.phase = .cancelled
                    $0.speed = nil
                    $0.eta = nil
                }
            } else {
                updateJob(job.id) {
                    $0.phase = .completed
                    $0.progress = 1
                    $0.speed = nil
                    $0.eta = nil
                }
            }
        } catch is CancellationError {
            updateJob(job.id) {
                $0.phase = .cancelled
                $0.speed = nil
                $0.eta = nil
            }
        } catch {
            if cancellationRequested {
                updateJob(job.id) {
                    $0.phase = .cancelled
                    $0.speed = nil
                    $0.eta = nil
                }
            } else {
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

        let json = try await processRunner.capture(executable: executable, arguments: [
            "--ignore-config",
            "--flat-playlist",
            "--dump-single-json",
            "--no-warnings",
            "--yes-playlist",
            url.absoluteString,
        ])
        return try YTDLPPlaylistParser.parse(json)
    }

    private func verify(executable: URL) async {
        do {
            let version = try await processRunner.capture(executable: executable, arguments: ["--version"])
            guard version.isEmpty == false else {
                throw ProcessExecutionError(exitCode: -1, message: "yt-dlp did not report a version.")
            }
            toolState = .ready(executable: executable, version: version)
        } catch {
            toolState = .failed(error.localizedDescription)
        }
    }

    private func consume(_ text: String, for jobID: UUID) {
        logText += text
        if logText.count > 50_000 {
            logText = String(logText.suffix(50_000))
        }

        for line in text.components(separatedBy: .newlines) {
            guard let parsed = YTDLPOutputParser.parse(line) else { continue }
            updateJob(jobID) { job in
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
}
