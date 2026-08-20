import AppKit
import UniformTypeIdentifiers

enum FilePickerService {
    static var romContentTypes: [UTType] {
        var types: [UTType] = [.item, .content, .data, .folder]
        for ext in ["3ds", "cia", "cci", "cxi"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    static func openFiles(completion: @escaping ([URL]) -> Void) {
        present(configure: { panel in
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.resolvesAliases = true
            panel.allowsOtherFileTypes = true
            panel.canCreateDirectories = false
            panel.prompt = "Add to Queue"
            panel.message = "Select 3DS ROM files, CIA packages, or folders containing them"
            panel.allowedContentTypes = romContentTypes
        }, completion: completion)
    }

    static func pickOutputFolder(current: URL?, completion: @escaping (URL?) -> Void) {
        present(configure: { panel in
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.resolvesAliases = true
            panel.prompt = "Select Output"
            panel.message = "Choose destination directory for forged ROMs"
            if let current {
                panel.directoryURL = current
            }
        }, completion: { urls in
            completion(urls.first)
        })
    }

    static func saveText(suggestedName: String, completion: @escaping (URL?) -> Void) {
        let work = {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = suggestedName
            attach(panel) { response, url in
                completion(response == .OK ? url : nil)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private static func present(configure: @escaping (NSOpenPanel) -> Void, completion: @escaping ([URL]) -> Void) {
        let work = {
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            configure(panel)
            attach(panel) { response, _ in
                completion(response == .OK ? panel.urls : [])
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private static func attach(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) {
        if let window = AppDelegate.shared?.window {
            panel.beginSheetModal(for: window) { response in
                completion(response, panel.url)
            }
        } else {
            panel.begin { response in
                completion(response, panel.url)
            }
        }
    }
}
