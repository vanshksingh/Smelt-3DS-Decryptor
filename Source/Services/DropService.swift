import AppKit
import UniformTypeIdentifiers

enum DropService {
    static func collect(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var collected: [URL] = []
        let lock = NSLock()

        func append(_ url: URL) {
            guard url.isFileURL || url.scheme == nil else { return }
            lock.lock()
            collected.append(ROMImport.normalize(url))
            lock.unlock()
        }

        for provider in providers {
            group.enter()
            resolve(provider) { url in
                if let url { append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(collected)
        }
    }

    private static func resolve(_ provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    completion(url)
                    return
                }
                loadFileURLItem(provider, completion: completion)
            }
            return
        }
        loadFileURLItem(provider, completion: completion)
    }

    private static func loadFileURLItem(_ provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                completion(url(from: item))
            }
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                completion(url(from: item))
            }
            return
        }
        completion(nil)
    }

    private static func url(from item: Any?) -> URL? {
        if let url = item as? URL { return url.standardizedFileURL }
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url.standardizedFileURL
        }
        if let string = item as? String {
            if string.hasPrefix("file://"), let url = URL(string: string) {
                return url.standardizedFileURL
            }
            return URL(fileURLWithPath: string).standardizedFileURL
        }
        return nil
    }
}
