import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case download
    case activity

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .download ? "arrow.down.to.line" : "clock.arrow.circlepath" }
}

extension Notification.Name {
    static let showDownloadSection = Notification.Name("PullDown.showDownloadSection")
    static let showActivitySection = Notification.Name("PullDown.showActivitySection")
    static let startConfiguredDownload = Notification.Name("PullDown.startConfiguredDownload")
}

struct PullDownCommands: Commands {
    @ObservedObject private var updater = UpdaterManager.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }

        CommandMenu("Navigate") {
            Button("New Download") {
                NotificationCenter.default.post(name: .showDownloadSection, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Activity") {
                NotificationCenter.default.post(name: .showActivitySection, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)
        }

        CommandMenu("Download") {
            Button("Download with Current Settings") {
                NotificationCenter.default.post(name: .startConfiguredDownload, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
