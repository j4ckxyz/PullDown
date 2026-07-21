import Foundation

enum YouTubeURLParser {
    static func parse(_ input: String) throws -> [URL] {
        let tokens = input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }

        var urls: [URL] = []
        var invalid: [String] = []

        for token in tokens {
            guard
                let components = URLComponents(string: token),
                let scheme = components.scheme?.lowercased(),
                scheme == "https" || scheme == "http",
                let host = components.host?.lowercased(),
                isYouTubeHost(host),
                let url = canonicalURL(from: components, host: host)
            else {
                invalid.append(token)
                continue
            }

            urls.append(url)
        }

        if tokens.isEmpty {
            throw PullDownError.invalidURLs(["No URL entered"])
        }
        if invalid.isEmpty == false {
            throw PullDownError.invalidURLs(invalid)
        }
        return urls
    }

    static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    static func containsPlaylist(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains(where: { $0.name == "list" && $0.value?.isEmpty == false }) == true
    }

    private static func canonicalURL(from components: URLComponents, host: String) -> URL? {
        let query = Dictionary(
            components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let listID = query["list"].flatMap(nonEmpty)
        let pathParts = components.path.split(separator: "/").map(String.init)

        let videoID: String?
        if host == "youtu.be" {
            videoID = pathParts.first.flatMap(nonEmpty)
        } else if components.path == "/watch" {
            videoID = query["v"].flatMap(nonEmpty)
        } else if ["shorts", "live", "embed"].contains(pathParts.first ?? ""), pathParts.count >= 2 {
            videoID = nonEmpty(pathParts[1])
        } else if components.path == "/playlist" {
            videoID = nil
        } else {
            return nil
        }

        guard videoID != nil || listID != nil else { return nil }

        var canonical = URLComponents()
        canonical.scheme = "https"
        canonical.host = "www.youtube.com"
        canonical.path = videoID == nil ? "/playlist" : "/watch"
        var items: [URLQueryItem] = []
        if let videoID { items.append(URLQueryItem(name: "v", value: videoID)) }
        if let listID { items.append(URLQueryItem(name: "list", value: listID)) }
        canonical.queryItems = items
        return canonical.url
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
