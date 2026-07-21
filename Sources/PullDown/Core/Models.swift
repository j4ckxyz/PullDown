import Foundation

enum MediaKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case video
    case audio

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .video ? "film" : "waveform" }
}

enum VideoQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case best
    case ultraHD = "2160"
    case quadHD = "1440"
    case fullHD = "1080"
    case HD = "720"
    case SD = "480"

    var id: Self { self }

    var title: String {
        switch self {
        case .best: "Best available"
        case .ultraHD: "4K · 2160p"
        case .quadHD: "1440p"
        case .fullHD: "1080p"
        case .HD: "720p"
        case .SD: "480p"
        }
    }

    var maximumHeight: Int? { Int(rawValue) }
}

enum VideoContainer: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case mp4
    case mkv
    case webm

    var id: Self { self }
    var title: String { rawValue == "automatic" ? "Automatic" : rawValue.uppercased() }
}

enum AudioFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case m4a
    case mp3
    case opus
    case flac
    case wav
    case aac

    var id: Self { self }
    var title: String { rawValue.uppercased() }
}

enum AudioQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case best = "0"
    case kbps320 = "320K"
    case kbps256 = "256K"
    case kbps192 = "192K"
    case kbps128 = "128K"
    case kbps96 = "96K"

    var id: Self { self }
    var title: String { self == .best ? "Best available" : rawValue.replacingOccurrences(of: "K", with: " kbps") }
}

struct DownloadOptions: Equatable, Sendable {
    var videoQuality: VideoQuality = .best
    var videoContainer: VideoContainer = .automatic
    var audioFormat: AudioFormat = .m4a
    var audioQuality: AudioQuality = .best
    var downloadPlaylist = false
    var playlistItems: [Int]?
    var embedMetadata = true
    var embedThumbnail = true
    var includeSubtitles = false
    var concurrentFragments = 4
    var filenameTemplate = "%(title)s [%(id)s].%(ext)s"
}

struct PlaylistVideo: Identifiable, Equatable, Sendable {
    let index: Int
    let videoID: String
    let title: String
    let duration: Double?

    var id: Int { index }

    var durationText: String? {
        guard let duration else { return nil }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlaylistInfo: Equatable, Sendable {
    let title: String
    let videos: [PlaylistVideo]
}

struct DownloadRequest: Equatable, Sendable {
    let urls: [URL]
    let kind: MediaKind
    let destination: URL
    let options: DownloadOptions
}

struct CommandSpec: Equatable, Sendable {
    let executable: URL
    let arguments: [String]
}

enum ToolState: Equatable, Sendable {
    case checking
    case missing
    case installing
    case ready(executable: URL, version: String)
    case failed(String)

    var executable: URL? {
        guard case let .ready(executable, _) = self else { return nil }
        return executable
    }

    var isReady: Bool { executable != nil }
}

enum DownloadPhase: Equatable, Sendable {
    case queued
    case downloading
    case processing
    case completed
    case cancelled
    case failed(String)

    var title: String {
        switch self {
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .processing: "Finishing"
        case .completed: "Complete"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}

struct DownloadJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let request: DownloadRequest
    let createdAt: Date
    var phase: DownloadPhase
    var progress: Double
    var speed: String?
    var eta: String?
    var outputPath: String?

    init(request: DownloadRequest) {
        id = UUID()
        self.request = request
        createdAt = Date()
        phase = .queued
        progress = 0
    }
}

enum ProcessEvent: Equatable, Sendable {
    case standardOutput(String)
    case standardError(String)
}

struct ProcessExecutionError: LocalizedError, Equatable, Sendable {
    let exitCode: Int32
    let message: String

    var errorDescription: String? {
        message.isEmpty ? "yt-dlp exited with status \(exitCode)." : message
    }
}

enum PullDownError: LocalizedError, Equatable, Sendable {
    case invalidURLs([String])
    case toolUnavailable
    case downloadAlreadyRunning
    case invalidResponse
    case checksumUnavailable
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case let .invalidURLs(values): "These are not supported YouTube URLs: \(values.joined(separator: ", "))"
        case .toolUnavailable: "yt-dlp is not ready yet."
        case .downloadAlreadyRunning: "Another download is already running."
        case .invalidResponse: "The yt-dlp download server returned an invalid response."
        case .checksumUnavailable: "The official checksum list did not contain yt-dlp_macos."
        case .checksumMismatch: "The downloaded yt-dlp binary did not match the official SHA-256 checksum."
        }
    }
}

enum AppPreferenceKeys {
    static let menuBarEnabled = "menuBarEnabled"
    static let destinationPath = "destinationPath"
    static let defaultMediaKind = "defaultMediaKind"
}

enum AppDefaults {
    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads", directoryHint: .isDirectory)
    }
}
