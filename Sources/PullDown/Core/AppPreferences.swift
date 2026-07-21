import Foundation

/// Lightweight, synchronous persistence for remembered download settings and
/// saved presets, backed by `UserDefaults` with JSON payloads.
struct AppPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Remembered per-tab options

    func rememberedOptions(for kind: MediaKind) -> DownloadOptions? {
        guard let data = defaults.data(forKey: key(for: kind)) else { return nil }
        return try? JSONDecoder().decode(DownloadOptions.self, from: data)
    }

    func setRememberedOptions(_ options: DownloadOptions, for kind: MediaKind) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        defaults.set(data, forKey: key(for: kind))
    }

    private func key(for kind: MediaKind) -> String {
        switch kind {
        case .video: AppPreferenceKeys.rememberedVideoOptions
        case .audio: AppPreferenceKeys.rememberedAudioOptions
        }
    }

    // MARK: Presets

    func loadPresets() -> [DownloadPreset] {
        guard let data = defaults.data(forKey: AppPreferenceKeys.presets) else { return [] }
        return (try? JSONDecoder().decode([DownloadPreset].self, from: data)) ?? []
    }

    func savePresets(_ presets: [DownloadPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: AppPreferenceKeys.presets)
    }

    var didSeedPresets: Bool {
        get { defaults.bool(forKey: AppPreferenceKeys.didSeedPresets) }
        nonmutating set { defaults.set(newValue, forKey: AppPreferenceKeys.didSeedPresets) }
    }
}

enum PresetTransfer {
    static func encode(_ presets: [DownloadPreset]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(presets)
    }

    static func decode(_ data: Data) throws -> [DownloadPreset] {
        try JSONDecoder().decode([DownloadPreset].self, from: data)
    }
}
