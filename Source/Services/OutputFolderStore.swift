import Foundation

enum OutputFolderStore {
    private static let pathKey = "smelt.outputFolderPath"
    private static let bookmarkKey = "smelt.outputFolderBookmark"
    private static let modeKey = "smelt.outputMode"

    static func saveMode(_ mode: Settings.OutMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
    }

    static func loadMode() -> Settings.OutMode {
        guard let raw = UserDefaults.standard.string(forKey: modeKey),
              let mode = Settings.OutMode(rawValue: raw) else {
            return .same
        }
        return mode
    }

    static func save(_ url: URL?) {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: pathKey)
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }

        UserDefaults.standard.set(url.path, forKey: pathKey)
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
    }

    static func load() -> URL? {
        if let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url.standardizedFileURL
            }
        }

        if let path = UserDefaults.standard.string(forKey: pathKey) {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }

        return nil
    }
}
