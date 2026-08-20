import Foundation

/// Keeps security-scoped file URLs alive for the lifetime of the queue.
final class SecurityScopedAccess {
    private var counts: [URL: Int] = [:]
    private let lock = NSLock()

    @discardableResult
    func retain(_ url: URL) -> URL {
        let key = url.standardizedFileURL
        lock.lock()
        let next = (counts[key] ?? 0) + 1
        if counts[key] == nil {
            _ = key.startAccessingSecurityScopedResource()
        }
        counts[key] = next
        lock.unlock()
        return key
    }

    func retain(_ urls: [URL]) -> [URL] {
        urls.map { retain($0) }
    }

    func release(_ url: URL) {
        let key = url.standardizedFileURL
        lock.lock()
        guard let current = counts[key] else {
            lock.unlock()
            return
        }
        if current <= 1 {
            counts[key] = nil
            lock.unlock()
            key.stopAccessingSecurityScopedResource()
        } else {
            counts[key] = current - 1
            lock.unlock()
        }
    }

    func releaseAll() {
        lock.lock()
        let snapshot = counts
        counts.removeAll()
        lock.unlock()
        snapshot.keys.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    deinit {
        releaseAll()
    }
}
