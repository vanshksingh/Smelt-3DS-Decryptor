import Foundation

final class Settings: ObservableObject {
    enum OutMode: String, CaseIterable {
        case same = "Same as Source"
        case custom = "Custom Folder"
    }

    @Published var mode: OutMode = .same
    @Published var folder: URL?
    @Published var suffix: String = " Decrypted"
    @Published var autoOpen: Bool = false
    @Published var showConsole: Bool = false
    @Published var globalFormat: OutputFormat = .same
}
