import Foundation

protocol DownloadHistoryStoring: Sendable {
    func load() async throws -> [DownloadHistoryItem]
    func save(_ items: [DownloadHistoryItem]) async throws
}

actor DownloadHistoryStore: DownloadHistoryStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = DownloadHistoryStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [DownloadHistoryItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.pullDown.decode([DownloadHistoryItem].self, from: data)
    }

    func save(_ items: [DownloadHistoryItem]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pullDown.encode(items)
        try data.write(to: fileURL, options: .atomic)
    }

    nonisolated static func defaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support
            .appendingPathComponent("PullDown", isDirectory: true)
            .appendingPathComponent("download-history.json")
    }
}

private extension JSONEncoder {
    static var pullDown: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var pullDown: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
