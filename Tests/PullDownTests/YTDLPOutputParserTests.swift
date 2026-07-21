import Testing
@testable import PullDown

struct YTDLPOutputParserTests {
    @Test func parsesProgressSpeedAndETA() throws {
        let result = try #require(YTDLPOutputParser.parse("[download]  42.5% of 12.00MiB at 3.25MiB/s ETA 00:07"))
        #expect(result.progress == 0.425)
        #expect(result.speed == "3.25MiB/s")
        #expect(result.eta == "00:07")
    }

    @Test func parsesQuotedMergedOutputPath() throws {
        let result = try #require(YTDLPOutputParser.parse("[Merger] Merging formats into \"/Users/test/Downloads/Example.mp4\""))
        #expect(result.outputPath == "/Users/test/Downloads/Example.mp4")
        #expect(result.isPostProcessing)
    }

    @Test func parsesPlaylistItemPosition() throws {
        let result = try #require(YTDLPOutputParser.parse("[download] Downloading item 3 of 12"))
        #expect(result.playlistIndex == 3)
        #expect(result.playlistCount == 12)
        #expect(result.progress == nil)
    }

    @Test func ignoresUnrelatedLogLine() {
        #expect(YTDLPOutputParser.parse("Loading cookies") == nil)
    }
}
