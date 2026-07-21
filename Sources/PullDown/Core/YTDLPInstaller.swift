import CryptoKit
import Foundation

protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPFetching {
    func data(from url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PullDownError.invalidResponse
        }
        return (data, httpResponse)
    }
}

protocol YTDLPInstalling: Sendable {
    func install(into directory: URL) async throws -> URL
}

actor YTDLPInstaller: YTDLPInstalling {
    static let binaryURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    static let checksumsURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS")!

    private let client: any HTTPFetching

    init(client: any HTTPFetching = URLSessionHTTPClient()) {
        self.client = client
    }

    func install(into directory: URL) async throws -> URL {
        async let binaryResponse = client.data(from: Self.binaryURL)
        async let checksumsResponse = client.data(from: Self.checksumsURL)

        let ((binary, binaryHTTP), (checksums, checksumsHTTP)) = try await (binaryResponse, checksumsResponse)
        guard binaryHTTP.statusCode == 200, checksumsHTTP.statusCode == 200 else {
            throw PullDownError.invalidResponse
        }

        guard
            let checksumText = String(data: checksums, encoding: .utf8),
            let expectedChecksum = Self.checksum(for: "yt-dlp_macos", in: checksumText)
        else {
            throw PullDownError.checksumUnavailable
        }

        guard Self.sha256Hex(of: binary) == expectedChecksum.lowercased() else {
            throw PullDownError.checksumMismatch
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "yt-dlp", directoryHint: .notDirectory)
        let temporary = directory.appending(path: ".yt-dlp-\(UUID().uuidString)", directoryHint: .notDirectory)
        try binary.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: temporary.path)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        return destination
    }

    static func checksum(for filename: String, in contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let listedFilename = fields.last.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if listedFilename == filename {
                return String(fields[0])
            }
        }
        return nil
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
