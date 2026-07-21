import AppKit
import SwiftUI

/// A single-emoji field with a button that opens the native macOS
/// Emoji & Symbols palette.
struct EmojiField: View {
    @Binding var emoji: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("🙂", text: Binding(
                get: { emoji },
                set: { emoji = Self.lastEmoji(in: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .font(.title2)
            .frame(width: 60)
            .focused($focused)

            Button {
                focused = true
                DispatchQueue.main.async {
                    NSApp.orderFrontCharacterPalette(nil)
                }
            } label: {
                Label("Choose…", systemImage: "face.smiling")
            }
        }
    }

    /// Keeps only the final grapheme so the field always holds one emoji.
    private static func lastEmoji(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : String(trimmed.suffix(1))
    }
}

struct PresetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let mediaKind: MediaKind
    let onSave: (_ name: String, _ emoji: String, _ tintHex: String?) -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var color: Color

    init(
        title: String,
        mediaKind: MediaKind,
        name: String,
        emoji: String,
        tintHex: String?,
        onSave: @escaping (String, String, String?) -> Void
    ) {
        self.title = title
        self.mediaKind = mediaKind
        self.onSave = onSave
        _name = State(initialValue: name)
        _emoji = State(initialValue: emoji)
        _color = State(initialValue: Color(presetHex: tintHex))
    }

    private var resolvedEmoji: String {
        emoji.isEmpty ? (mediaKind == .video ? "🎬" : "🎵") : emoji
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.25))
                        .overlay(Circle().stroke(color, lineWidth: 1.5))
                    Text(resolvedEmoji)
                        .font(.title)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Preset name" : name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    Text(mediaKind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Name", text: $name)
                LabeledContent("Icon") { EmojiField(emoji: $emoji) }
                ColorPicker("Colour", selection: $color, supportsOpacity: false)
            }
            .formStyle(.grouped)
            .frame(height: 150)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name, resolvedEmoji, color.presetHexString)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
