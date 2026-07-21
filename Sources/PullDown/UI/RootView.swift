import AppKit
import SwiftUI

struct RootView: View {
    @Environment(PullDownModel.self) private var model
    @AppStorage(AppPreferenceKeys.destinationPath) private var destinationPath = AppDefaults.downloadsDirectory.path
    @State private var selection: AppSection = .download

    var body: some View {
        ZStack {
            PullDownWindowBackground()

            VStack(spacing: 0) {
                switch selection {
                case .download:
                    DownloadView(draft: model.downloadDraft)
                case .activity:
                    ActivityView()
                }

                Divider()
                HStack(spacing: 8) {
                    ToolStatusView(state: model.toolState, compact: true)
                    Spacer()
                    if model.toolState.isReady == false {
                        Button("Install yt-dlp") {
                            Task { await model.installYTDLP() }
                        }
                        .controlSize(.small)
                        .disabled(model.toolState == .installing || model.toolState == .checking)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(.ultraThinMaterial)
            }
        }
        .alert("PullDown", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if $0 == false { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $selection) {
                    ForEach(AppSection.allCases) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("PullDown section")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NSWorkspace.shared.open(AppDefaults.downloadsDirectory)
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Open Downloads folder")
                .accessibilityInputLabels(["Open Downloads folder", "Downloads"])

                Button {
                    Task { await model.bootstrap(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Check yt-dlp again")
                .accessibilityInputLabels(["Check yt-dlp again", "Refresh"])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDownloadSection)) { _ in
            selection = .download
        }
        .onReceive(NotificationCenter.default.publisher(for: .showActivitySection)) { _ in
            selection = .activity
        }
        .onReceive(NotificationCenter.default.publisher(for: .startConfiguredDownload)) { _ in
            guard model.canStartDraftDownload else { return }
            Task { await model.startDraftDownload(destinationPath: destinationPath) }
        }
    }
}
