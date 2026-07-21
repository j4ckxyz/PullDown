import AppKit
import SwiftUI

private enum SidebarDestination: String, CaseIterable, Identifiable {
    case download
    case activity

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .download ? "arrow.down.to.line" : "clock.arrow.circlepath" }
}

struct RootView: View {
    @Environment(PullDownModel.self) private var model
    @State private var selection: SidebarDestination? = .download

    var body: some View {
        VStack(spacing: 0) {
            switch selection ?? .download {
            case .download:
                DownloadView()
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
                    ForEach(SidebarDestination.allCases) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .tag(Optional(destination))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("PullDown section")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NSWorkspace.shared.open(AppDefaults.downloadsDirectory)
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Open Downloads folder") // [VERIFY] confirm label matches intent
                .accessibilityInputLabels(["Open Downloads folder", "Downloads"])

                Button {
                    Task { await model.bootstrap(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Check yt-dlp again") // [VERIFY] confirm label matches intent
                .accessibilityInputLabels(["Check yt-dlp again", "Refresh"])
            }
        }
    }
}
