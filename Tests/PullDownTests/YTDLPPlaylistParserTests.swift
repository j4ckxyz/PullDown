import Testing
@testable import PullDown

struct YTDLPPlaylistParserTests {
    @Test func parsesFlatPlaylistMetadataForSelection() throws {
        let json = """
        {
          "title": "Example playlist",
          "entries": [
            {"id":"first","title":"First video","duration":62.0,"playlist_index":1},
            {"id":"second","title":"Second video","duration":125.0,"playlist_index":2}
          ]
        }
        """

        let playlist = try YTDLPPlaylistParser.parse(json)

        #expect(playlist.title == "Example playlist")
        #expect(playlist.videos.map(\.index) == [1, 2])
        #expect(playlist.videos.map(\.title) == ["First video", "Second video"])
        #expect(playlist.videos.map(\.durationText) == ["1:02", "2:05"])
    }

    @Test func skipsUnavailablePlaylistEntries() throws {
        let json = """
        {"title":"Partial playlist","entries":[null,{"id":"available","title":"Available"}]}
        """
        let playlist = try YTDLPPlaylistParser.parse(json)
        #expect(playlist.videos.count == 1)
        #expect(playlist.videos.first?.index == 2)
    }

    @Test func preservesEveryEntryInALargePlaylist() throws {
        let entries = (1...89).map { index in
            "{\"id\":\"video-\(index)\",\"title\":\"Video \(index)\",\"playlist_index\":\(index)}"
        }
        let json = "{\"title\":\"Large playlist\",\"entries\":[\(entries.joined(separator: ","))]}"

        let playlist = try YTDLPPlaylistParser.parse(json)

        #expect(playlist.videos.count == 89)
        #expect(playlist.videos.first?.index == 1)
        #expect(playlist.videos.last?.index == 89)
    }
}
