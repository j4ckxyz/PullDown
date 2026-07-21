import Foundation

enum YTDLPCommandBuilder {
    static func makeCommand(
        executable: URL,
        request: DownloadRequest,
        ffmpegExecutable: URL?
    ) -> CommandSpec {
        var arguments = [
            "--ignore-config",
            "--newline",
            "--no-color",
            "--progress",
            "--paths", request.destination.path,
            "--output", request.options.filenameTemplate,
            "--concurrent-fragments", String(request.options.concurrentFragments),
        ]

        let isPlaylistDownload = request.options.downloadPlaylist
            || (request.options.playlistItems?.isEmpty == false)

        if let playlistItems = request.options.playlistItems, playlistItems.isEmpty == false {
            arguments.append(contentsOf: [
                "--yes-playlist",
                "--playlist-items", playlistItems.sorted().map(String.init).joined(separator: ","),
            ])
        } else {
            arguments.append(request.options.downloadPlaylist ? "--yes-playlist" : "--no-playlist")
        }

        // In a playlist a single private or unavailable video should not abort
        // the whole batch — skip it and keep going.
        if isPlaylistDownload {
            arguments.append("--ignore-errors")
        }

        if let ffmpegExecutable {
            arguments.append(contentsOf: ["--ffmpeg-location", ffmpegExecutable.path])
        }

        switch request.kind {
        case .video:
            arguments.append(contentsOf: ["--format", videoFormat(for: request.options.videoQuality)])
            if request.options.videoContainer != .automatic {
                arguments.append(contentsOf: ["--merge-output-format", request.options.videoContainer.rawValue])
            }
        case .audio:
            arguments.append(contentsOf: [
                "--extract-audio",
                "--audio-format", request.options.audioFormat.rawValue,
                "--audio-quality", request.options.audioQuality.rawValue,
            ])
        }

        if request.options.embedMetadata {
            arguments.append("--embed-metadata")
        }
        if request.options.embedThumbnail {
            arguments.append("--embed-thumbnail")
        }
        if request.options.includeSubtitles, request.kind == .video {
            arguments.append(contentsOf: [
                "--write-subs",
                "--write-auto-subs",
                "--sub-langs", "all,-live_chat",
                "--embed-subs",
            ])
        }

        arguments.append(contentsOf: request.urls.map(\.absoluteString))
        return CommandSpec(executable: executable, arguments: arguments)
    }

    static func videoFormat(for quality: VideoQuality) -> String {
        guard let height = quality.maximumHeight else { return "bv*+ba/b" }
        return "bv*[height<=\(height)]+ba/b[height<=\(height)]"
    }
}
