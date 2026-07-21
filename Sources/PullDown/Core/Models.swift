import Foundation
import Observation

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

struct DownloadOptions: Equatable, Codable, Sendable {
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

struct DownloadRequest: Equatable, Codable, Sendable {
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
    var playlistIndex: Int?
    var playlistCount: Int?
    var attemptedItemCount = 0
    var failedItemCount = 0

    init(request: DownloadRequest) {
        id = UUID()
        self.request = request
        createdAt = Date()
        phase = .queued
        progress = 0
    }

    /// Overall progress across a playlist: completed items plus the fraction of
    /// the current item. Falls back to the single-file progress when this is not
    /// a playlist download.
    var overallProgress: Double {
        guard let playlistCount, let playlistIndex, playlistCount > 0 else { return progress }
        let completed = Double(playlistIndex - 1)
        return min(max((completed + progress) / Double(playlistCount), 0), 1)
    }

    /// A human summary when some playlist items were skipped, e.g.
    /// "10 of 15 downloaded · 5 skipped". Nil when nothing was skipped.
    var completionSummary: String? {
        guard failedItemCount > 0 else { return nil }
        let total = playlistCount ?? attemptedItemCount
        guard total > 0 else { return nil }
        let succeeded = max(total - failedItemCount, 0)
        return "\(succeeded) of \(total) downloaded · \(failedItemCount) skipped"
    }
}

@Observable
@MainActor
final class DownloadDraft {
    var urlInput = ""
    var mediaKind: MediaKind = .video
    var options = DownloadOptions()
    var showsAdvanced = false
    var playlistInfo: PlaylistInfo?
    var selectedPlaylistIndices = Set<Int>()
    var loadedPlaylistURL: URL?
    var isLoadingPlaylist = false
    var didLoadPreferences = false
}

enum DownloadHistoryStatus: String, Codable, Sendable {
    case completed
    case cancelled
    case failed

    var title: String {
        switch self {
        case .completed: "Complete"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}

struct DownloadHistoryItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let request: DownloadRequest
    let startedAt: Date
    let finishedAt: Date
    let status: DownloadHistoryStatus
    let outputPath: String?
    let failureMessage: String?
    let noteMessage: String?

    init?(job: DownloadJob, finishedAt: Date = Date()) {
        let status: DownloadHistoryStatus
        let failureMessage: String?
        switch job.phase {
        case .completed:
            status = .completed
            failureMessage = nil
        case .cancelled:
            status = .cancelled
            failureMessage = nil
        case let .failed(message):
            status = .failed
            failureMessage = message
        case .queued, .downloading, .processing:
            return nil
        }

        id = job.id
        request = job.request
        startedAt = job.createdAt
        self.finishedAt = finishedAt
        self.status = status
        outputPath = job.outputPath
        self.failureMessage = failureMessage
        noteMessage = status == .completed ? job.completionSummary : nil
    }

    var displayName: String {
        if request.options.downloadPlaylist {
            return "Playlist download"
        }
        if let outputPath {
            return URL(fileURLWithPath: outputPath).lastPathComponent
        }
        return request.urls.first?.host ?? request.kind.title
    }

    var destinationURL: URL {
        URL(fileURLWithPath: request.destination.path, isDirectory: true)
    }

    var outputURL: URL? {
        guard request.options.downloadPlaylist == false else { return nil }
        return outputPath.map { URL(fileURLWithPath: $0) }
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

struct DownloadPreset: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var mediaKind: MediaKind
    var options: DownloadOptions
    var emoji: String?
    var tintHex: String?
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mediaKind: MediaKind,
        options: DownloadOptions,
        emoji: String? = nil,
        tintHex: String? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mediaKind = mediaKind
        self.options = options
        self.emoji = emoji
        self.tintHex = tintHex
        self.isBuiltIn = isBuiltIn
    }

    /// The emoji to show, falling back to a media-kind default.
    var displayEmoji: String {
        if let emoji, emoji.isEmpty == false { return emoji }
        return mediaKind == .video ? "🎬" : "🎵"
    }
}

extension DownloadPreset {
    /// Stable identifiers so built-ins can be recognised across launches and
    /// restored without duplicating.
    static let builtIns: [DownloadPreset] = [
        DownloadPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Best video (MP4)",
            mediaKind: .video,
            options: {
                var options = DownloadOptions()
                options.videoQuality = .best
                options.videoContainer = .mp4
                return options
            }(),
            emoji: "🎬",
            tintHex: "#FF6B4A",
            isBuiltIn: true
        ),
        DownloadPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
            name: "1080p MP4",
            mediaKind: .video,
            options: {
                var options = DownloadOptions()
                options.videoQuality = .fullHD
                options.videoContainer = .mp4
                return options
            }(),
            emoji: "📺",
            tintHex: "#3B82F6",
            isBuiltIn: true
        ),
        DownloadPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
            name: "Video + subtitles",
            mediaKind: .video,
            options: {
                var options = DownloadOptions()
                options.videoQuality = .best
                options.videoContainer = .mp4
                options.includeSubtitles = true
                return options
            }(),
            emoji: "💬",
            tintHex: "#8B5CF6",
            isBuiltIn: true
        ),
        DownloadPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            name: "MP3 audio (320 kbps)",
            mediaKind: .audio,
            options: {
                var options = DownloadOptions()
                options.audioFormat = .mp3
                options.audioQuality = .kbps320
                return options
            }(),
            emoji: "🎧",
            tintHex: "#10B981",
            isBuiltIn: true
        ),
        DownloadPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            name: "M4A audio (best)",
            mediaKind: .audio,
            options: {
                var options = DownloadOptions()
                options.audioFormat = .m4a
                options.audioQuality = .best
                return options
            }(),
            emoji: "🎵",
            tintHex: "#F59E0B",
            isBuiltIn: true
        ),
    ]
}

enum AppPreferenceKeys {
    static let menuBarEnabled = "menuBarEnabled"
    static let destinationPath = "destinationPath"
    static let defaultMediaKind = "defaultMediaKind"
    static let rememberedVideoOptions = "rememberedOptions.video"
    static let rememberedAudioOptions = "rememberedOptions.audio"
    static let presets = "downloadPresets"
    static let didSeedPresets = "didSeedPresets"
}

enum AppDefaults {
    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads", directoryHint: .isDirectory)
    }
}
