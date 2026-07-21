import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updater = UpdaterManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        updater.start()
    }
}

@main
struct PullDownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: PullDownModel
    @AppStorage(AppPreferenceKeys.menuBarEnabled) private var menuBarEnabled = true

    init() {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKeys.menuBarEnabled: true,
            AppPreferenceKeys.destinationPath: AppDefaults.downloadsDirectory.path,
            AppPreferenceKeys.defaultMediaKind: MediaKind.video.rawValue,
        ])
        _model = State(initialValue: PullDownModel())
    }

    var body: some Scene {
        WindowGroup("PullDown", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 460, idealWidth: 560, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            PullDownCommands()
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarDownloadView()
                .environment(model)
                .task { await model.bootstrap() }
        } label: {
            Label("PullDown", systemImage: model.isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 520, height: 400)
                .task { await model.bootstrap() }
        }
    }
}
