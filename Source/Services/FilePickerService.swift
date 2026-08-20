import AppKit
import UniformTypeIdentifiers

enum FilePickerService {
    static func openFiles(from window: NSWindow? = nil, completion: @escaping ([URL]) -> Void) {
        let panel = makeROMPanel()
        present(panel, from: window) { response in
            guard response == .OK else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let picked = panel.urls.map { url -> URL in
                _ = url.startAccessingSecurityScopedResource()
                return ROMImport.normalize(url)
            }
            DispatchQueue.main.async {
                completion(picked)
            }
        }
    }

    static func pickOutputFolder(current: URL?, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true
        panel.prompt = "Select Output"
        panel.message = "Choose destination directory for forged ROMs"
        panel.title = "Choose Output Folder"
        if let current {
            panel.directoryURL = current
        }
        present(panel, from: NSApp.keyWindow) { response in
            DispatchQueue.main.async {
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    static func saveText(suggestedName: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = suggestedName
        present(panel, from: NSApp.keyWindow) { response in
            DispatchQueue.main.async {
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    private static func makeROMPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.canCreateDirectories = false
        panel.prompt = "Add to Queue"
        panel.message = "Select 3DS ROM files, CIA packages, or folders containing them"
        panel.title = "Add ROMs"
        // Do not filter by UTType here — .3ds/.cia often have no stable type.
        // AppState validates extensions after the user picks files.
        return panel
    }

    private static func present(
        _ panel: NSSavePanel,
        from window: NSWindow?,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        let work = {
            NSApp.activate(ignoringOtherApps: true)
            let host = window ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
            host?.makeKeyAndOrderFront(nil)
            completion(panel.runModal())
        }
        DispatchQueue.main.async(execute: work)
    }
}
