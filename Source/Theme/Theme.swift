import SwiftUI

struct Palette: Equatable {
    let scheme: ColorScheme

    var isDark: Bool { scheme == .dark }

    var background: Color {
        isDark
            ? Color(red: 0.05, green: 0.05, blue: 0.08)
            : Color(red: 0.94, green: 0.94, blue: 0.97)
    }

    var card: Color {
        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.035)
    }

    var cardHover: Color {
        isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }

    var dropFill: Color {
        isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.025)
    }

    var dropFillActive: Color {
        isDark ? Color.white.opacity(0.05) : Palette.blue.opacity(0.08)
    }

    var textPrimary: Color {
        isDark ? Color.white.opacity(0.95) : Color(red: 0.10, green: 0.10, blue: 0.14)
    }

    var textSecondary: Color {
        isDark ? Color.white.opacity(0.62) : Color.black.opacity(0.58)
    }

    var textTertiary: Color {
        isDark ? Color.white.opacity(0.42) : Color.black.opacity(0.42)
    }

    var textFaint: Color {
        isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.28)
    }

    var inverted: Color {
        isDark ? Color.white : Color.black
    }

    var onAccent: Color { .white }

    var border: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var fieldFill: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    var chipFill: Color {
        isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }

    var toolbarFill: Color {
        isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.03)
    }

    var statusFill: Color {
        isDark ? Color.black.opacity(0.22) : Color.white.opacity(0.55)
    }

    var consoleChrome: Color {
        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
    }

    var consoleFill: Color {
        Color(red: 0.07, green: 0.08, blue: 0.10)
    }

    var overlayScrim: Color {
        isDark ? Color.black.opacity(0.72) : Color.black.opacity(0.45)
    }

    var licenseFill: Color {
        isDark ? background : Color(red: 0.97, green: 0.97, blue: 0.99)
    }

    var headerScrim: Color { background }

    var disabledFill: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    var disabledStroke: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var dropStroke: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    static let blue = Color(red: 0.18, green: 0.72, blue: 1.0)
    static let purple = Color(red: 0.65, green: 0.38, blue: 1.0)
    static let green = Color(red: 0.22, green: 0.78, blue: 0.48)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.14)
    static let red = Color(red: 0.95, green: 0.32, blue: 0.38)
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(scheme: .dark)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
