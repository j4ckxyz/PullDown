import Foundation
import Observation

@Observable
@MainActor
final class PullDownModel {
    private(set) var toolState: ToolState = .checking
    private(set) var ffmpegExecutable: URL?
    private(set) var jobs: [DownloadJob] = []
    private(set) var logText = ""
    var errorMessage: String?

    private let ytDLPExecutableLocator: any ExecutableLocating
    private let ffmpegExecutableLocator: any ExecutableLocating
    private let installer: any YTDLPInstalling
    private let processRunner: any ProcessRunning
    private let managedBinDirectory: URL
    private var didBootstrap = false
    private var currentJobID: UUID?
    private var cancellationRequested = false

    init(
        ytDLPExecutableLocator: any ExecutableLocating = ExecutableLocator(),
        ffmpegExecutableLocator: any ExecutableLocating = ExecutableLocator(),
        installer: any YTDLPInstalling = YTDLPInstaller(),
        processRunner: any ProcessRunning = ProcessRunner(),
        managedBinDirectory: URL = ExecutableLocator.defaultManagedBinDirectory()
    ) {
        self.ytDLPExecutableLocator = ytDLPExecutableLocator
        self.ffmpegExecutableLocator = ffmpegExecutableLocator
        self.installer = installer
        self.processRunner = processRunner
        self.managedBinDirectory = managedBinDirectory
    }

    var isDownloading: Bool { currentJobID != nil }

    func bootstrap(force: Bool = false) async {
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
            updateJob(job.id) {
                $0.phase = .completed
                $0.progress = 1
            }
        } catch is CancellationError {
            updateJob(job.id) { $0.phase = .cancelled }
        } catch {
            if cancellationRequested {
                updateJob(job.id) { $0.phase = .cancelled }
            } else {
                updateJob(job.id) { $0.phase = .failed(error.localizedDescription) }
                errorMessage = error.localizedDescription
            }
        }

        currentJobID = nil
        cancellationRequested = false
    }

    func cancelDownload() async {
        guard let currentJobID else { return }
        cancellationRequested = true
        updateJob(currentJobID) { $0.phase = .cancelled }
        await processRunner.cancel()
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
                if parsed.isPostProcessing { job.phase = .processing }
            }
        }
    }

    private func updateJob(_ id: UUID, update: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        update(&jobs[index])
    }
}
