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

    private var headerSummary: QueueToolbarSummary {
        QueueToolbarSummary(
            pending: st.pendingCount,
            busy: st.busy,
            hasDone: st.files.contains { $0.state == .done || $0.state == .skipped },
            hasFiles: !st.files.isEmpty,
            destinationTitle: destinationTitle
        )
    }

    private var destinationTitle: String {
        if st.settings.mode == .same {
            return "Destination: Same as Source"
        }
        if let folder = st.settings.folder {
            return "Destination: \(folder.lastPathComponent)"
        }
        return "Destination: Choose Folder..."
    }

    private var headerCallbacks: HeaderCallbacks {
        HeaderCallbacks(
            run: { st.run() },
            sameDestination: { st.useSameOutputFolder() },
            chooseDestination: pickCustomOutputFolder,
            formatChanged: { st.requeueIfNeeded(for: $0) },
            clearDone: { st.clearDone() },
            clearAll: { st.clearAll() }
        )
    }

    private var toolbarSnapshot: ToolbarSnapshot {
        ToolbarSnapshot(
            destinationTitle: destinationTitle,
            suffix: st.settings.suffix,
            format: st.settings.globalFormat,
            autoOpen: st.settings.autoOpen,
            showConsole: st.settings.showConsole,
            hasDone: st.files.contains { $0.state == .done || $0.state == .skipped },
            hasFiles: !st.files.isEmpty,
            busy: st.busy
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                settings: st.settings,
                summary: headerSummary,
                toolbarSnapshot: toolbarSnapshot,
                callbacks: headerCallbacks
            )
            MainContentView(st: st, settings: st.settings)
            StatusBarView(st: st)
        }
        .background(palette.background)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.windows.forEach { window in
                    WindowInteraction.fillContentView(window)
                    window.contentView?.layoutSubtreeIfNeeded()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openROMPicker)) { _ in
            FilePickerService.openFiles(from: NSApp.keyWindow) { urls in
                guard !urls.isEmpty else { return }
                st.add(urls)
            }
        }
    }

    private func pickCustomOutputFolder() {
        FilePickerService.pickOutputFolder(current: st.settings.folder) { selected in
            DispatchQueue.main.async {
                if let selected {
                    st.setCustomOutputFolder(selected)
                } else if st.settings.folder == nil {
                    st.useSameOutputFolder()
                }
            }
        }
    }
}
