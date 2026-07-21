import Foundation
import Testing
@testable import PullDown

struct AppPreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "PullDownTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func remembersOptionsPerMediaKindSeparately() {
        let preferences = AppPreferences(defaults: makeDefaults())

        var video = DownloadOptions()
        video.videoQuality = .fullHD
        var audio = DownloadOptions()
        audio.audioFormat = .mp3

        preferences.setRememberedOptions(video, for: .video)
        preferences.setRememberedOptions(audio, for: .audio)

        #expect(preferences.rememberedOptions(for: .video)?.videoQuality == .fullHD)
        #expect(preferences.rememberedOptions(for: .audio)?.audioFormat == .mp3)
    }

    @Test func returnsNilForUnsetOptions() {
        let preferences = AppPreferences(defaults: makeDefaults())
        #expect(preferences.rememberedOptions(for: .video) == nil)
    }

    @Test func savesAndLoadsPresets() {
        let preferences = AppPreferences(defaults: makeDefaults())
        let preset = DownloadPreset(name: "My preset", mediaKind: .audio, options: DownloadOptions())

        preferences.savePresets([preset])

        let loaded = preferences.loadPresets()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "My preset")
    }

    @Test func presetTransferRoundTrips() throws {
        let presets = DownloadPreset.builtIns
        let data = try PresetTransfer.encode(presets)
        let decoded = try PresetTransfer.decode(data)
        #expect(decoded == presets)
    }
}
