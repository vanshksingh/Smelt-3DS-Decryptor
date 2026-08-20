import Foundation

enum ROMImport {
    static let extensions: Set<String> = ["3ds", "cia", "cci", "cxi"]

    enum Failure: Error, CustomStringConvertible {
        case unsupportedExtension(String)
        case notFound
        case isDirectory
        case notReadable
        case iCloudPlaceholder
        case emptyFile

        var description: String {
            switch self {
            case .unsupportedExtension(let ext):
                return ext.isEmpty ? "missing extension" : "unsupported extension .\(ext)"
            case .notFound: return "not found"
            case .isDirectory: return "expected a file"
            case .notReadable: return "not readable"
            case .iCloudPlaceholder:
                return "file is still downloading from iCloud — wait a moment and add it again"
            case .emptyFile: return "empty file"
            }
        }
    }

    /// Picker/drop URLs may be file-reference URLs where `.path` is unreliable.
    static func normalize(_ url: URL) -> URL {
        if let pathURL = (url as NSURL).filePathURL as URL? {
            return pathURL.standardizedFileURL
        }
        if url.isFileURL {
            return url.standardizedFileURL
        }
        if url.scheme == nil, !url.path.isEmpty {
            return URL(fileURLWithPath: url.path).standardizedFileURL
        }
        return url.standardizedFileURL
    }

    static func extensionOf(_ url: URL) -> String {
        normalize(url).pathExtension.lowercased()
    }

    static func isSupported(_ url: URL) -> Bool {
        extensions.contains(extensionOf(url))
    }

    static func validateFile(_ url: URL) -> Result<(URL, Int64), Failure> {
        let file = normalize(url)
        let ext = file.pathExtension.lowercased()
        guard extensions.contains(ext) else {
            return .failure(.unsupportedExtension(ext))
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else {
            return .failure(.notFound)
        }
        if isDirectory.boolValue { return .failure(.isDirectory) }

        let size = resolvedFileSize(file)
        guard size > 0 else {
            if requestICloudDownloadIfNeeded(file) {
                return .failure(.iCloudPlaceholder)
            }
            return .failure(.emptyFile)
        }

        if canReadBytes(from: file) {
            return .success((file, size))
        }

        if requestICloudDownloadIfNeeded(file) {
            return .failure(.iCloudPlaceholder)
        }

        if FileManager.default.isReadableFile(atPath: file.path) {
            return .success((file, size))
        }

        return .failure(.notReadable)
    }

    /// iCloud metadata often says "not downloaded" even when the bytes are local.
    /// Trust an actual read probe over `ubiquitousItemDownloadingStatus`.
    private static func canReadBytes(from file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let sample = try? handle.read(upToCount: 512) else { return false }
        return !sample.isEmpty
    }

    private static func resolvedFileSize(_ file: URL) -> Int64 {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let bytes = attrs[.size] as? NSNumber,
           bytes.int64Value > 0 {
            return bytes.int64Value
        }
        if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .totalFileSizeKey]) {
            if let fileSize = values.fileSize, fileSize > 0 {
                return Int64(fileSize)
            }
            if let total = values.totalFileSize, total > 0 {
                return Int64(total)
            }
            if let allocated = values.totalFileAllocatedSize, allocated > 0 {
                return Int64(allocated)
            }
        }
        return 0
    }

    @discardableResult
    private static func requestICloudDownloadIfNeeded(_ file: URL) -> Bool {
        guard let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus else {
            return false
        }
        guard status == .notDownloaded else { return false }
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        return true
    }
}
