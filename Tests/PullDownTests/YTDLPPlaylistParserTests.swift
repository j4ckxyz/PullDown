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

    @Test func preservesRealTitlesBeyondTheInitialPlaylistEntries() throws {
        let json = """
        {
          "title": "Queen instrumental",
          "entries": [
            {"id":"fifteen","title":"Queen instrumental - Friends Will Be Friends","duration":259,"playlist_index":15},
            {"id":"sixteen","title":"Queen instrumental - Dragon Attack","duration":264,"playlist_index":16},
            {"id":"seventeen","title":"Queen instrumental - Get Down, Make Love","duration":229,"playlist_index":17},
            {"id":"eighteen","title":"Queen instrumental - Gimme The Prize (Kurgan's Theme)","duration":255,"playlist_index":18},
            {"id":"nineteen","title":"Queen instrumental - Hammer To Fall","duration":276,"playlist_index":19}
          ]
        }
        """

        let playlist = try YTDLPPlaylistParser.parse(json)

        #expect(playlist.videos.map(\.title) == [
            "Queen instrumental - Friends Will Be Friends",
            "Queen instrumental - Dragon Attack",
            "Queen instrumental - Get Down, Make Love",
            "Queen instrumental - Gimme The Prize (Kurgan's Theme)",
            "Queen instrumental - Hammer To Fall",
        ])
    }
}
