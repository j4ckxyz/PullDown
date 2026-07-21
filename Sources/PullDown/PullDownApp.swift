import SwiftUI

@main
struct PullDownApp: App {
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
                .frame(minWidth: 620, minHeight: 500)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 720, height: 640)
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
