import Foundation

/// Keeps security-scoped file URLs alive for the lifetime of the queue.
final class SecurityScopedAccess {
    private var urls: Set<URL> = []
    private let lock = NSLock()

    @discardableResult
    func retain(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        _ = standardized.startAccessingSecurityScopedResource()
        lock.lock()
        urls.insert(standardized)
        lock.unlock()
        return standardized
    }

    func retain(_ urls: [URL]) -> [URL] {
        urls.map { retain($0) }
    }

    func release(_ url: URL) {
        let standardized = url.standardizedFileURL
        lock.lock()
        let shouldStop = urls.remove(standardized) != nil
        lock.unlock()
        if shouldStop {
            standardized.stopAccessingSecurityScopedResource()
        }
    }

    func releaseAll() {
        lock.lock()
        let snapshot = urls
        urls.removeAll()
        lock.unlock()
        snapshot.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    deinit {
        releaseAll()
    }
}
