import AppKit
import UniformTypeIdentifiers

enum FilePickerService {
    static var romContentTypes: [UTType] {
        var types: [UTType] = [.folder]
        for ext in ["3ds", "cia", "cci", "cxi"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        types.append(.data)
        return types
    }

    static func openFiles(from window: NSWindow? = nil, completion: @escaping ([URL]) -> Void) {
        let panel = makeROMPanel()
        present(panel, from: window, deferToNextTurn: false) { response in
            completion(response == .OK ? panel.urls : [])
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
        present(panel, from: NSApp.keyWindow, deferToNextTurn: true) { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    static func saveText(suggestedName: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = suggestedName
        present(panel, from: NSApp.keyWindow, deferToNextTurn: false) { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    private static func makeROMPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = false
        panel.prompt = "Add to Queue"
        panel.message = "Select 3DS ROM files, CIA packages, or folders containing them"
        panel.allowedContentTypes = romContentTypes
        return panel
    }

    /// Menus must close before a modal panel; button clicks must open immediately.
    private static func present(
        _ panel: NSSavePanel,
        from window: NSWindow?,
        deferToNextTurn: Bool,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        let work = {
            NSApp.activate(ignoringOtherApps: true)
            let host = window ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
            if let host {
                WindowInteraction.prepare(host)
                host.makeKeyAndOrderFront(nil)
            }
            completion(panel.runModal())
        }
        if deferToNextTurn {
            DispatchQueue.main.async(execute: work)
        } else if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
