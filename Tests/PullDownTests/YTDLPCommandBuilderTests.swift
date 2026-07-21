import Foundation
import Testing
@testable import PullDown

struct YTDLPCommandBuilderTests {
    private let executable = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
    private let destination = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
    private let videoURL = URL(string: "https://youtu.be/example")!

    @Test func videoCommandCapsResolutionAndConfiguresContainer() {
        var options = DownloadOptions()
        options.videoQuality = .fullHD
        options.videoContainer = .mp4
        options.includeSubtitles = true
        let request = DownloadRequest(urls: [videoURL], kind: .video, destination: destination, options: options)

        let command = YTDLPCommandBuilder.makeCommand(
            executable: executable,
            request: request,
            ffmpegExecutable: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        )

        #expect(command.executable == executable)
        #expect(command.arguments.contains("bv*[height<=1080]+ba/b[height<=1080]"))
        #expect(command.arguments.contains("--merge-output-format"))
        #expect(command.arguments.contains("mp4"))
        #expect(command.arguments.contains("--embed-subs"))
        #expect(command.arguments.suffix(1) == [videoURL.absoluteString])
    }

    @Test func audioCommandUsesRequestedEncodingSettings() {
        var options = DownloadOptions()
        options.audioFormat = .mp3
        options.audioQuality = .kbps320
        let request = DownloadRequest(urls: [videoURL], kind: .audio, destination: destination, options: options)
        let command = YTDLPCommandBuilder.makeCommand(executable: executable, request: request, ffmpegExecutable: nil)

        #expect(command.arguments.contains("--extract-audio"))
        #expect(value(after: "--audio-format", in: command.arguments) == "mp3")
        #expect(value(after: "--audio-quality", in: command.arguments) == "320K")
        #expect(command.arguments.contains("--embed-subs") == false)
    }

    @Test func pastedContentRemainsOneProcessArgument() {
        let unusualURL = URL(string: "https://www.youtube.com/watch?v=abc&list=one%20two")!
        let request = DownloadRequest(urls: [unusualURL], kind: .video, destination: destination, options: DownloadOptions())
        let command = YTDLPCommandBuilder.makeCommand(executable: executable, request: request, ffmpegExecutable: nil)

        #expect(command.arguments.last == unusualURL.absoluteString)
        #expect(command.arguments.contains("/bin/sh") == false)
        #expect(command.arguments.contains("-c") == false)
    }

    @Test func selectedPlaylistVideosBecomePlaylistItemsArgument() {
        var options = DownloadOptions()
        options.downloadPlaylist = true
        options.playlistItems = [7, 2, 4]
        let playlistURL = URL(string: "https://www.youtube.com/watch?v=example&list=playlist")!
        let request = DownloadRequest(urls: [playlistURL], kind: .video, destination: destination, options: options)
        let command = YTDLPCommandBuilder.makeCommand(executable: executable, request: request, ffmpegExecutable: nil)

        #expect(value(after: "--playlist-items", in: command.arguments) == "2,4,7")
        #expect(command.arguments.contains("--yes-playlist"))
        #expect(command.arguments.contains("--no-playlist") == false)
    }

    @Test func playlistDownloadsSkipUnavailableVideos() {
        var options = DownloadOptions()
        options.downloadPlaylist = true
        let playlistURL = URL(string: "https://www.youtube.com/playlist?list=example")!
        let request = DownloadRequest(urls: [playlistURL], kind: .video, destination: destination, options: options)
        let command = YTDLPCommandBuilder.makeCommand(executable: executable, request: request, ffmpegExecutable: nil)

        #expect(command.arguments.contains("--ignore-errors"))
    }

    @Test func singleVideoDownloadsDoNotIgnoreErrors() {
        let request = DownloadRequest(urls: [videoURL], kind: .video, destination: destination, options: DownloadOptions())
        let command = YTDLPCommandBuilder.makeCommand(executable: executable, request: request, ffmpegExecutable: nil)

        #expect(command.arguments.contains("--ignore-errors") == false)
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
