import Foundation
import Testing
@testable import PullDown

private struct StubLocator: ExecutableLocating {
    let values: [String: URL]
    func locate(named name: String) -> URL? { values[name] }
}

private struct StubInstaller: YTDLPInstalling {
    let result: URL
    func install(into directory: URL) async throws -> URL { result }
}

private actor StubProcessRunner: ProcessRunning {
    let capturedVersion: String
    let emittedEvents: [ProcessEvent]
    private(set) var commands: [CommandSpec] = []
    private(set) var wasCancelled = false

    init(capturedVersion: String = "2026.06.09", emittedEvents: [ProcessEvent] = []) {
        self.capturedVersion = capturedVersion
        self.emittedEvents = emittedEvents
    }

    func events(for command: CommandSpec) async throws -> AsyncThrowingStream<ProcessEvent, Error> {
        commands.append(command)
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ProcessEvent.self)
        for event in emittedEvents { continuation.yield(event) }
        continuation.finish()
        return stream
    }

    func capture(executable: URL, arguments: [String]) async throws -> String { capturedVersion }
    func cancel() async { wasCancelled = true }
}

private actor InMemoryHistoryStore: DownloadHistoryStoring {
    private var items: [DownloadHistoryItem]

    init(items: [DownloadHistoryItem] = []) {
        self.items = items
    }

    func load() -> [DownloadHistoryItem] { items }
    func save(_ items: [DownloadHistoryItem]) { self.items = items }
}

@MainActor
struct PullDownModelTests {
    @Test func bootstrapDiscoversAndVerifiesTools() async {
        let ytDLP = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let runner = StubProcessRunner()
        let model = PullDownModel(
            ytDLPExecutableLocator: StubLocator(values: ["yt-dlp": ytDLP]),
            ffmpegExecutableLocator: StubLocator(values: ["ffmpeg": ffmpeg]),
            installer: StubInstaller(result: ytDLP),
            processRunner: runner,
            historyStore: InMemoryHistoryStore(),
            managedBinDirectory: URL(fileURLWithPath: "/managed")
        )

        await model.bootstrap()

        #expect(model.toolState == .ready(executable: ytDLP, version: "2026.06.09"))
        #expect(model.ffmpegExecutable == ffmpeg)
    }

    @Test func successfulDownloadUpdatesProgressAndOutput() async throws {
        let ytDLP = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        let runner = StubProcessRunner(emittedEvents: [
            .standardOutput("[download]  50.0% of 10MiB at 2MiB/s ETA 00:03\n"),
            .standardOutput("[Merger] Merging formats into \"/Users/test/Downloads/Example.mp4\"\n"),
        ])
        let model = PullDownModel(
            ytDLPExecutableLocator: StubLocator(values: ["yt-dlp": ytDLP]),
            ffmpegExecutableLocator: StubLocator(values: [:]),
            installer: StubInstaller(result: ytDLP),
            processRunner: runner,
            historyStore: InMemoryHistoryStore(),
            managedBinDirectory: URL(fileURLWithPath: "/managed")
        )
        await model.bootstrap()
        let url = try #require(URL(string: "https://youtu.be/example"))
        let request = DownloadRequest(
            urls: [url],
            kind: .video,
            destination: URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true),
            options: DownloadOptions()
        )

        await model.startDownload(request)

        let job = try #require(model.jobs.first)
        #expect(job.phase == .completed)
        #expect(job.progress == 1)
        #expect(job.outputPath == "/Users/test/Downloads/Example.mp4")
        #expect(job.speed == nil)
        #expect(job.eta == nil)
        #expect(model.history.count == 1)
        #expect(model.history.first?.status == .completed)
        #expect(model.history.first?.outputPath == "/Users/test/Downloads/Example.mp4")
        #expect(await runner.commands.count == 1)
    }

    @Test func draftSurvivesNavigationViewRecreation() {
        let model = PullDownModel(historyStore: InMemoryHistoryStore())
        model.downloadDraft.urlInput = "https://www.youtube.com/watch?v=example"
        model.downloadDraft.mediaKind = .audio
        model.downloadDraft.options.audioFormat = .flac

        let sameDraft = model.downloadDraft

        #expect(sameDraft.urlInput == "https://www.youtube.com/watch?v=example")
        #expect(sameDraft.mediaKind == .audio)
        #expect(sameDraft.options.audioFormat == .flac)
    }
}
