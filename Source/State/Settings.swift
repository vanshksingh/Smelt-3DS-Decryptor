import Foundation

final class Settings: ObservableObject {
    enum OutMode: String, CaseIterable {
        case same = "Same as Source"
        case custom = "Custom Folder"
    }

    @Published var mode: OutMode {
        didSet { OutputFolderStore.saveMode(mode) }
    }

    @Published var folder: URL? {
        didSet { OutputFolderStore.save(folder) }
    }

    @Published var suffix: String = " Decrypted"
    @Published var autoOpen: Bool = false
    @Published var showConsole: Bool = false
    @Published var globalFormat: OutputFormat = .same

    init() {
        mode = OutputFolderStore.loadMode()
        folder = OutputFolderStore.load()
        if mode == .custom && folder == nil {
            mode = .same
        }
    }

    func setCustomFolder(_ url: URL) {
        folder = url.standardizedFileURL
        mode = .custom
    }

    func useSameAsSource() {
        mode = .same
    }

    var customFolderIsValid: Bool {
        guard mode == .custom, let folder else { return mode == .same }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isWritableFile(atPath: folder.path)
    }
}
