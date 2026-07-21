import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

            PresetsView()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }

            LogsView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
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

struct PresetsView: View {
    @Environment(PullDownModel.self) private var model
    @State private var statusMessage: String?
    @State private var editingPreset: DownloadPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Presets")
                    .font(.headline)
                Spacer()
                Button("Import…", systemImage: "square.and.arrow.down") { importPresets() }
                Button("Export…", systemImage: "square.and.arrow.up") { exportPresets() }
                    .disabled(model.presets.isEmpty)
            }
            .labelStyle(.titleAndIcon)

            if model.presets.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No presets yet.")
                        .foregroundStyle(.secondary)
                    Text("Save one from the download screen, or restore the built-in presets.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                List {
                    ForEach(model.presets) { preset in
                        PresetRow(preset: preset) { editingPreset = preset }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 180)
            }

            HStack {
                Button("Restore built-in presets") { model.restoreBuiltInPresets() }
                Spacer()
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Presets store the download type and every format option under a name. Built-in presets are marked and can be renamed or deleted like any other.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .sheet(item: $editingPreset) { preset in
            PresetEditorSheet(
                title: "Edit preset",
                mediaKind: preset.mediaKind,
                name: preset.name,
                emoji: preset.displayEmoji,
                tintHex: preset.tintHex
            ) { name, emoji, tintHex in
                model.updatePreset(id: preset.id, name: name, emoji: emoji, tintHex: tintHex)
            }
        }
    }

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.title = "Export presets"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "PullDown-presets.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportPresets(to: url)
            statusMessage = "Exported \(model.presets.count) preset(s)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.title = "Import presets"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try model.importPresets(from: url)
            statusMessage = count > 0 ? "Imported \(count) preset(s)." : "No presets found in that file."
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

private struct PresetRow: View {
    @Environment(PullDownModel.self) private var model
    let preset: DownloadPreset
    let onEdit: () -> Void

    private var tint: Color { Color(presetHex: preset.tintHex) }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .overlay(Circle().stroke(tint.opacity(0.7), lineWidth: 1))
                Text(preset.displayEmoji)
                    .font(.body)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(preset.mediaKind.title)
                    Text("·")
                    Text(summary)
                    if preset.isBuiltIn {
                        Text("·")
                        Text("Built-in")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Button("Edit…", action: onEdit)
                .buttonStyle(.borderless)

            Button(role: .destructive) {
                model.deletePreset(id: preset.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(preset.name)")
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        switch preset.mediaKind {
        case .video:
            let quality = preset.options.videoQuality.title
            let container = preset.options.videoContainer.title
            return preset.options.includeSubtitles ? "\(quality) · \(container) · subs" : "\(quality) · \(container)"
        case .audio:
            return "\(preset.options.audioFormat.title) · \(preset.options.audioQuality.title)"
        }
    }
}

struct LogsView: View {
    @Environment(PullDownModel.self) private var model
    @State private var copiedConfirmation = false
    @State private var saveError: String?

    private let bottomAnchor = "logs-bottom-anchor"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ToolStatusView(state: model.toolState, compact: true)
                Spacer()
                if copiedConfirmation {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Button("Copy", systemImage: "doc.on.doc") { copyLogs() }
                    .disabled(model.logText.isEmpty)
                Button("Save…", systemImage: "square.and.arrow.down") { saveLogs() }
                    .disabled(model.logText.isEmpty)
                Button("Clear", systemImage: "trash", role: .destructive) { model.clearLogs() }
                    .disabled(model.logText.isEmpty)
            }
            .labelStyle(.titleAndIcon)

            logContent

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Logs record the exact yt-dlp command and its output so you can see why a download failed. Copy or save them to disk to share when troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var logContent: some View {
        if model.logText.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No activity logged yet.")
                    .foregroundStyle(.secondary)
                Text("Start a download and its progress will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        } else {
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    Text(model.logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: model.logText) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.logText, forType: .string)
        withAnimation { copiedConfirmation = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copiedConfirmation = false }
        }
    }

    private func saveLogs() {
        saveError = nil
        let panel = NSSavePanel()
        panel.title = "Save PullDown logs"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "PullDown-log-\(Self.fileTimestamp()).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportLogs(to: url)
        } catch {
            saveError = "Could not save logs: \(error.localizedDescription)"
        }
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
