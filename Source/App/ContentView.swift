import SwiftUI
import AppKit

struct ContentView: View {
    @State private var hasAcceptedEULA = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: Palette {
        Palette(scheme: colorScheme)
    }

    var body: some View {
        Group {
            if hasAcceptedEULA {
                MainWorkspace()
            } else {
                LicenseGate {
                    hasAcceptedEULA = true
                }
            }
        }
        .frame(minWidth: 840, idealWidth: 920, minHeight: 560, idealHeight: 640)
        .background(palette.background.ignoresSafeArea())
        .background(WindowSyncView())
        .environment(\.palette, palette)
        .onAppear {
            UserDefaults.standard.removeObject(forKey: "hasAcceptedEULA_v1")
            UserDefaults.standard.removeObject(forKey: "appearancePreference")
        }
    }
}

struct MainWorkspace: View {
    @StateObject private var st = AppState()
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(st: st, settings: st.settings)
            MainContentView(st: st, settings: st.settings)
            StatusBarView(st: st)
        }
        .background(palette.background)
        .onAppear {
            NSApp.windows.forEach { WindowInteraction.fillContentView($0) }
            NSApp.windows.forEach { WindowInteraction.refreshTracking(in: $0.contentView) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openROMPicker)) { _ in
            guard !st.busy else { return }
            FilePickerService.openFiles(from: NSApp.keyWindow) { urls in
                st.add(urls)
            }
        }
    }
}
