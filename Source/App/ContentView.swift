import SwiftUI

struct ContentView: View {
    @StateObject private var st = AppState()
    @StateObject private var theme = ThemeManager()
    @AppStorage("hasAcceptedEULA_v1") private var hasAcceptedEULA = false
    @Environment(\.colorScheme) private var systemScheme

    private var resolvedScheme: ColorScheme {
        theme.resolvedScheme(system: systemScheme)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderView(st: st, settings: st.settings, theme: theme)
                MainContentView(st: st, settings: st.settings)
                StatusBarView(st: st)
            }
            .background(Palette(scheme: resolvedScheme).background)
            .allowsHitTesting(hasAcceptedEULA)
            .opacity(hasAcceptedEULA ? 1 : 0.35)

            if !hasAcceptedEULA {
                Palette(scheme: resolvedScheme).overlayScrim
                    .ignoresSafeArea()

                LicenseView(isPresented: Binding(
                    get: { !hasAcceptedEULA },
                    set: { presented in
                        withAnimation(.easeOut(duration: 0.25)) {
                            hasAcceptedEULA = !presented
                        }
                    }
                ))
                .zIndex(100)
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.palette, Palette(scheme: resolvedScheme))
        .environmentObject(theme)
        .preferredColorScheme(theme.preference.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .openROMPicker)) { _ in
            guard hasAcceptedEULA, !st.busy else { return }
            FilePickerService.openFiles { urls in
                st.add(urls)
            }
        }
    }
}
