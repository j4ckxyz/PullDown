# PullDown

PullDown is a compact, fully native SwiftUI front end for `yt-dlp`. It downloads YouTube video or audio without requiring Terminal, and includes an optional menu-bar companion.

![PullDown showing a selectable playlist](Assets/pulldown-main.png)

## What works

- Finds `yt-dlp` in standard macOS, Homebrew, MacPorts and Python installation paths, or installs a checksum-verified official build.
- Cleans shared links and removes tracking, timestamp and fragment parameters before downloading.
- Loads complete playlists, with Select all, Select none and individual video selection.
- Offers video quality and container controls, audio format and bitrate controls, metadata, thumbnails, subtitles and filename templates.
- Saves to Downloads by default or another folder chosen with the native macOS picker.
- Shows download progress, speed, ETA and recent activity.
- Provides the same core download controls from an optional menu-bar item, which can be disabled in Settings.
- Includes the supplied app artwork as a complete native macOS icon set, from 16 points through the 1024-pixel App Store rendition.
- Uses Liquid Glass on macOS 26 and newer, with native macOS materials on macOS 15–25.

PullDown is built with SwiftUI, AppKit integration and Foundation. It does not embed a browser or web interface, and it invokes `yt-dlp` directly without a shell.

## Requirements

- macOS 15 or later
- `yt-dlp`, installed automatically if required
- FFmpeg for audio conversion and merging separate high-quality video and audio streams
- Xcode 26 or later and Swift 6.2 or later when building from source

## Install from GitHub

Download the repository from GitHub, or clone it with:

```sh
gh repo clone j4ckxyz/PullDown
```

Open `PullDown.xcodeproj` in Xcode, choose the PullDown scheme, then Run. For a distributable build, use Product > Archive. PullDown is not sandboxed because it must discover package-manager executables and run `yt-dlp` outside the app container.

## URL handling

Shared links such as `https://youtu.be/8CENhRZmRBc?si=…` are reduced to the video URL. Playlist identifiers are retained, while tracking and start-time parameters such as `&t=182s` are removed.

## Tests

Run the Swift Testing suite with:

```sh
swift test
```

The tests cover the supplied shared link, playlist link and timestamp link, full playlist metadata parsing and selection, command construction, executable discovery, installation verification, progress parsing and a mocked end-to-end download.
