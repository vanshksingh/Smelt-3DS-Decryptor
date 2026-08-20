import SwiftUI

struct SecondaryActionStyle: ButtonStyle {
    var icon: String
    var color: Color
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            configuration.label
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(isEnabled ? color : palette.textFaint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(configuration.isPressed
                      ? color.opacity(0.2)
                      : (isHovered && isEnabled ? color.opacity(0.15) : color.opacity(0.08)))
        )
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            if isEnabled { isHovered = hovering }
        }
    }
}

struct PrimarySmeltButtonStyle: ButtonStyle {
    var isBusy: Bool
    var hasPending: Bool
    @State private var isHovered = false
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        let enabled = !isBusy && hasPending
        HStack(spacing: 8) {
            configuration.label
        }
        .font(.system(size: 14, weight: .black, design: .rounded))
        .foregroundColor(enabled ? palette.onAccent : palette.textFaint)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Group {
                if enabled {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: isHovered
                                ? [Palette.blue.opacity(1.15), Palette.purple.opacity(1.15)]
                                : [Palette.blue, Palette.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .shadow(color: Palette.blue.opacity(isHovered ? 0.55 : 0.28), radius: isHovered ? 12 : 6, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.disabledFill)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.disabledStroke, lineWidth: 1))
                }
            }
        )
        .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            if enabled { isHovered = hovering }
        }
    }
}
