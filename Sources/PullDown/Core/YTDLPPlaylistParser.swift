import Foundation

enum YTDLPPlaylistParser {
    private struct Payload: Decodable {
        let title: String?
        let entries: [Entry?]
    }

    private struct Entry: Decodable {
        let id: String
        let title: String?
        let duration: Double?
        let playlistIndex: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case duration
            case playlistIndex = "playlist_index"
        }
    }

    static func parse(_ json: String) throws -> PlaylistInfo {
        let payload = try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        let videos = payload.entries.enumerated().compactMap { offset, entry -> PlaylistVideo? in
            guard let entry else { return nil }
            return PlaylistVideo(
                index: entry.playlistIndex ?? offset + 1,
                videoID: entry.id,
                title: entry.title ?? "Untitled video",
                duration: entry.duration
            )
        }
        return PlaylistInfo(title: payload.title ?? "YouTube playlist", videos: videos)
    }
}
