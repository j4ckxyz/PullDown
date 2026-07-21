import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(PullDownModel.self) private var model
    @AppStorage(AppPreferenceKeys.menuBarEnabled) private var menuBarEnabled = true
    @AppStorage(AppPreferenceKeys.destinationPath) private var destinationPath = AppDefaults.downloadsDirectory.path
    @AppStorage(AppPreferenceKeys.defaultMediaKind) private var defaultMediaKind = MediaKind.video.rawValue

    var body: some View {
        TabView {
            Form {
                Section("Companion") {
                    Toggle("Show PullDown in the menu bar", isOn: $menuBarEnabled)
                    Text("The menu-bar companion shares downloads and progress with the main app. Turn it off to use PullDown only as a regular app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Defaults") {
                    Picker("Download type", selection: $defaultMediaKind) {
                        ForEach(MediaKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    LabeledContent("Save to") {
                        HStack {
                            Text(destinationPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…", action: chooseDestination)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("yt-dlp") {
                    ToolStatusView(state: model.toolState)
                    HStack {
                        Button("Check again") {
                            Task { await model.bootstrap(force: true) }
                        }
                        Spacer()
                        Button(model.toolState.isReady ? "Install latest verified release" : "Install verified release") {
                            Task { await model.installYTDLP() }
                        }
                        .disabled(model.toolState == .checking || model.toolState == .installing || model.isDownloading)
                    }
                }

                Section("FFmpeg") {
                    LabeledContent("Status") {
                        if let ffmpeg = model.ffmpegExecutable {
                            Label(ffmpeg.path, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not found", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("FFmpeg is needed for audio conversion, stream merging, thumbnails, and embedded metadata. Install it with Homebrew or MacPorts, then check again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
        }
        .padding(.top, 8)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose the default download folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationPath = url.path
    }
}
