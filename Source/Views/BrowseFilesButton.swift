import SwiftUI

/// Opens the shared ROM picker via notification so the panel always uses
/// the same code path as File > Add ROMs, even while the queue is updating.
struct BrowseFilesButton: View {
    var title: String = "Browse Files..."
    @Environment(\.palette) private var palette
    @State private var hovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openROMPicker, object: nil)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(hovered ? palette.onAccent : palette.textPrimary)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            hovered
                                ? LinearGradient(
                                    colors: [Palette.blue, Palette.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [palette.fieldFill, palette.fieldFill],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(hovered ? Palette.blue.opacity(0.9) : palette.border, lineWidth: hovered ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}
