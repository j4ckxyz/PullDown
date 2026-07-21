import Foundation
import Testing
@testable import PullDown

struct YouTubeURLParserTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
    ])
    func acceptsSupportedYouTubeHosts(input: String) throws {
        let urls = try YouTubeURLParser.parse(input)
        #expect(urls.count == 1)
    }

    @Test(arguments: [
        "",
        "not a url",
        "https://example.com/watch?v=123",
        "https://notyoutube.com/watch?v=123",
        "javascript:alert(1)",
    ])
    func rejectsUnsupportedInput(input: String) {
        #expect(throws: PullDownError.self) {
            try YouTubeURLParser.parse(input)
        }
    }

    @Test func parsesMultipleLinksSeparatedByWhitespace() throws {
        let urls = try YouTubeURLParser.parse("""
        https://youtu.be/first
        https://www.youtube.com/watch?v=second
        """)
        #expect(urls.map(\.absoluteString) == [
            "https://www.youtube.com/watch?v=first",
            "https://www.youtube.com/watch?v=second",
        ])
    }

    @Test func cleansAccountPersonalSharedLink() throws {
        let urls = try YouTubeURLParser.parse("https://youtu.be/8CENhRZmRBc?si=GudJD4n8yUfGYd8m")
        #expect(urls.map(\.absoluteString) == ["https://www.youtube.com/watch?v=8CENhRZmRBc"])
    }

    @Test func preservesVideoAndPlaylistIdentifiers() throws {
        let input = "https://www.youtube.com/watch?v=xVQrqAxdH9w&list=PLgvFSQ2xChFMcBRbCGOkNMbKxm0oJ2z3H"
        let urls = try YouTubeURLParser.parse(input)
        #expect(urls.map(\.absoluteString) == [input])
        #expect(YouTubeURLParser.containsPlaylist(try #require(urls.first)))
    }

    @Test func stripsTimestampAndTrackingParameters() throws {
        let urls = try YouTubeURLParser.parse("https://www.youtube.com/watch?v=CGau-uFETEY&t=182s")
        #expect(urls.map(\.absoluteString) == ["https://www.youtube.com/watch?v=CGau-uFETEY"])
    }
}
