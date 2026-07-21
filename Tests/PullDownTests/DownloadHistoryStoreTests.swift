import Foundation
import Testing
@testable import PullDown

struct DownloadHistoryStoreTests {
    @Test func roundTripsHistoryAsJSON() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PullDownHistoryTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DownloadHistoryStore(fileURL: fileURL)
        let videoURL = try #require(URL(string: "https://www.youtube.com/watch?v=example"))
        var job = DownloadJob(request: DownloadRequest(
            urls: [videoURL],
            kind: .video,
            destination: URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true),
            options: DownloadOptions()
        ))
        job.phase = .completed
        job.outputPath = "/Users/test/Downloads/Example.mp4"
        let item = try #require(DownloadHistoryItem(job: job))

        try await store.save([item])
        let restored = try await store.load()

        let restoredItem = try #require(restored.first)
        #expect(restored.count == 1)
        #expect(restoredItem.id == item.id)
        #expect(restoredItem.request == item.request)
        #expect(restoredItem.status == .completed)
        #expect(restoredItem.outputPath == "/Users/test/Downloads/Example.mp4")
    }
}
