import AppKit
import SwiftUI

private final class PullDownVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}

private struct PullDownVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PullDownVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct PullDownWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                ZStack {
                    PullDownVisualEffectBackground()
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(0.18)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct PullDownCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let padding: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), reduceTransparency == false {
            content
                .padding(padding)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(padding)
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.separator.opacity(0.55), lineWidth: 1)
                }
        }
    }
}

extension View {
    func pullDownCard(cornerRadius: CGFloat = 18, padding: CGFloat = 18) -> some View {
        modifier(PullDownCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    @ViewBuilder
    func pullDownPrimaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func pullDownSecondaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

struct ToolStatusView: View {
    let state: ToolState
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            if compact == false {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(title)
                    .font(.caption.weight(.medium))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch state {
        case .checking: "Checking yt-dlp"
        case .missing: "yt-dlp needed"
        case .installing: "Installing yt-dlp"
        case .ready: "yt-dlp ready"
        case .failed: "yt-dlp problem"
        }
    }

    private var detail: String? {
        switch state {
        case let .ready(executable, version): "\(version) · \(executable.path)"
        case let .failed(message): message
        case .missing: "Install the verified official release to continue"
        case .installing: "Verifying the official macOS binary"
        case .checking: "Searching Homebrew, MacPorts, PATH, and user locations"
        }
    }

    private var symbol: String {
        switch state {
        case .checking, .installing: "arrow.triangle.2.circlepath"
        case .missing: "exclamationmark.triangle.fill"
        case .ready: "checkmark.seal.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch state {
        case .ready: .green
        case .missing: .orange
        case .failed: .red
        case .checking, .installing: .accentColor
        }
    }
}

struct EmptyActivityView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No downloads yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Paste a YouTube URL to start your first download.")
        }
    }
}
