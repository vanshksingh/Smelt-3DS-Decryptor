import SwiftUI
import AppKit

struct QueueToolbarSummary: Equatable {
    var pending: Int
    var busy: Bool
    var hasDone: Bool
    var hasFiles: Bool
    var destinationTitle: String
}

struct HeaderCallbacks {
    var run: () -> Void
    var sameDestination: () -> Void
    var chooseDestination: () -> Void
    var formatChanged: (OutputFormat) -> Void
    var clearDone: () -> Void
    var clearAll: () -> Void
}

struct HeaderView: View {
    let settings: Settings
    let summary: QueueToolbarSummary
    let toolbarSnapshot: ToolbarSnapshot
    let callbacks: HeaderCallbacks
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let image = CoverArt.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Palette.purple.opacity(0.9), Palette.blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 140)
                }
                LinearGradient(colors: [.clear, palette.headerScrim], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)

                HStack(alignment: .bottom) {
                    titleBlock
                    Spacer()
                    smeltButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(height: 140)

            NativeToolbar(settings: settings, snapshot: toolbarSnapshot, callbacks: callbacks)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.toolbarFill)
                .overlay(Rectangle().frame(height: 1).foregroundColor(palette.border), alignment: .bottom)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Smelt")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            Text("3DS Decryptor & Flag Injector")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var smeltButton: some View {
        Button(action: callbacks.run) {
            HStack(spacing: 8) {
                if summary.busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "bolt.fill")
                }
                Text(summary.busy ? "Smelting..." : "Smelt All\(summary.pending > 0 ? " (\(summary.pending))" : "")")
            }
        }
        .buttonStyle(PrimarySmeltButtonStyle(isBusy: summary.busy, hasPending: summary.pending > 0))
        .disabled(summary.busy || summary.pending == 0)
        .contentShape(Rectangle())
    }
}

private enum CoverArt {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "cover", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
