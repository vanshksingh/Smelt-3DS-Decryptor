import SwiftUI
import AppKit

final class AppState: ObservableObject {
    @Published var files: [ROM] = []
    @Published var busy = false
    @Published var console = ""

    let settings = Settings()
    let scopedAccess = SecurityScopedAccess()

    init() {
        if let folder = settings.folder {
            scopedAccess.retain(folder)
        }
    }

    func setCustomOutputFolder(_ url: URL) {
        if let existing = settings.folder {
            scopedAccess.release(existing)
        }
        let retained = scopedAccess.retain(url)
        settings.setCustomFolder(retained)
    }

    func useSameOutputFolder() {
        if let existing = settings.folder {
            scopedAccess.release(existing)
            settings.folder = nil
        }
        settings.useSameAsSource()
    }

    var pendingCount: Int {
        files.filter { $0.state == .queued || $0.state == .failed }.count
    }

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let retained = scopedAccess.retain(urls)

        DispatchQueue.global(qos: .userInitiated).async {
            var prepared: [ROM] = []

            for url in retained {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

                if isDirectory.boolValue {
                    guard let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for case let child as URL in enumerator {
                        if let rom = self.prepareROM(child) {
                            prepared.append(rom)
                        }
                    }
                } else if let rom = self.prepareROM(url) {
                    prepared.append(rom)
                }
            }

            DispatchQueue.main.async {
                let newcomers = prepared.filter { candidate in
                    !self.files.contains(where: { $0.url == candidate.url })
                }

                guard !newcomers.isEmpty else {
                    if prepared.isEmpty {
                        self.log("No .3ds, .cia, .cci, or .cxi files found in that selection.")
                        self.settings.showConsole = true
                    }
                    return
                }

                self.files.append(contentsOf: newcomers)
                self.log("Queued \(newcomers.count) ROM(s).")
                for rom in newcomers {
                    self.scan(romID: rom.id)
                }
                self.badge()
            }
        }
    }

    private func prepareROM(_ url: URL) -> ROM? {
        let retained = scopedAccess.retain(url)
        let ext = retained.pathExtension.lowercased()
        guard ["3ds", "cia", "cci", "cxi"].contains(ext) else { return nil }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: retained.path)[.size] as? Int64) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        var rom = ROM(url: retained, name: retained.lastPathComponent, ext: ext.uppercased(), size: size)
        if ext == "cia" {
            rom.analysis = .cia
            rom.state = .queued
        }
        return rom
    }

    func scan(romID: UUID) {
        update(id: romID) { $0.state = .scanning }
        guard let url = files.first(where: { $0.id == romID })?.url else { return }

        DispatchQueue.global(qos: .utility).async {
            let analysis = ROMAnalyzer.analyze(url)
            let metadata = ROMAnalyzer.extractMetadata(url)

            DispatchQueue.main.async {
                self.update(id: romID) { rom in
                    rom.analysis = analysis
                    if let titleID = metadata.titleID { rom.titleID = titleID }
                    if let productCode = metadata.productCode { rom.productCode = productCode }
                    if analysis == .clean {
                        rom.state = .done
                        rom.note = "Already fully decrypted"
                    } else {
                        rom.state = .queued
                    }
                }
                self.badge()
            }
        }
    }

    func remove(_ rom: ROM) {
        files.removeAll { $0.id == rom.id }
        scopedAccess.release(rom.url)
        badge()
    }

    func clearAll() {
        guard !busy else { return }
        files.removeAll()
        scopedAccess.releaseAll()
        badge()
    }

    func clearDone() {
        guard !busy else { return }
        let removed = files.filter { $0.state == .done || $0.state == .skipped }
        files.removeAll { $0.state == .done || $0.state == .skipped }
        removed.forEach { scopedAccess.release($0.url) }
        badge()
    }

    func bindingFor(_ romID: UUID) -> Binding<ROM> {
        Binding(
            get: {
                self.files.first(where: { $0.id == romID })
                    ?? ROM(url: URL(fileURLWithPath: ""), name: "", ext: "", size: "")
            },
            set: { newValue in
                if let idx = self.files.firstIndex(where: { $0.id == romID }) {
                    self.files[idx] = newValue
                }
            }
        )
    }

    func requeueIfNeeded(for format: OutputFormat) {
        for index in files.indices {
            let expected = files[index].expectedOutputExt(globalFormat: format)
            let current = files[index].outputURL?.pathExtension.lowercased() ?? files[index].ext.lowercased()
            if current != expected.lowercased() {
                files[index].state = .queued
                files[index].note = ""
                files[index].progress = 0
            }
        }
        badge()
    }

    func log(_ message: String) {
        let stamp: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: Date())
        }()
        DispatchQueue.main.async {
            self.console += "[\(stamp)] \(message)\n"
        }
    }

    func badge() {
        let count = files.filter { $0.state == .queued || $0.state == .running }.count
        DispatchQueue.main.async {
            NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
    }

    func run() {
        guard !busy else { return }
        let pending = files.filter { $0.state == .queued || $0.state == .failed }
        guard !pending.isEmpty else { return }

        do {
            try ToolchainService.verify()
        } catch {
            log(error.localizedDescription)
            settings.showConsole = true
            return
        }

        if settings.mode == .custom {
            guard settings.customFolderIsValid, let folder = settings.folder else {
                log("Custom output folder is missing or not writable. Choose another destination.")
                settings.showConsole = true
                return
            }
            log("Output destination: \(folder.path)")
        }

        busy = true
        for index in files.indices where files[index].state == .failed {
            files[index].state = .queued
            files[index].note = ""
            files[index].logs = []
        }

        log("Batch processing started — targeting \(pending.count) ROM container(s)")

        DispatchQueue.global(qos: .userInitiated).async {
            let processor = ROMProcessor(
                settings: self.settings,
                log: { self.log($0) },
                setProgress: { self.setProgress(id: $0, $1) }
            )

            for rom in pending {
                DispatchQueue.main.async {
                    self.update(id: rom.id) { item in
                        item.state = .running
                        item.progress = 0
                    }
                    self.badge()
                }

                self.log("Initializing operation for \(rom.name)...")
                let start = Date()
                do {
                    let output = try processor.process(rom)
                    let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))

                    if let output {
                        let metadata = ROMAnalyzer.extractMetadata(output)
                        DispatchQueue.main.async {
                            self.update(id: rom.id) { item in
                                if let titleID = metadata.titleID { item.titleID = titleID }
                                if let productCode = metadata.productCode { item.productCode = productCode }
                            }
                        }
                    }

                    DispatchQueue.main.async {
                        self.update(id: rom.id) { item in
                            item.state = output == nil ? .skipped : .done
                            item.outputURL = output
                            item.note = output?.lastPathComponent ?? item.note
                            item.progress = 1.0
                            switch item.analysis {
                            case .patch: item.analysis = .patched
                            case .decrypt: item.analysis = .decrypted
                            case .cia: item.analysis = .processed
                            default: break
                            }
                        }
                        self.badge()
                    }
                    self.log("Successfully processed \(rom.name) in \(elapsed)s")
                } catch {
                    DispatchQueue.main.async {
                        self.update(id: rom.id) { item in
                            item.state = .failed
                            item.note = error.localizedDescription
                            item.logs.append(error.localizedDescription)
                        }
                        self.badge()
                    }
                    self.log("Failed on \(rom.name): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                self.busy = false
                self.badge()
                self.log("Batch process complete.")
                if self.settings.autoOpen,
                   let folder = self.files.compactMap({ $0.outputURL?.deletingLastPathComponent() }).first {
                    NSWorkspace.shared.open(folder)
                }
            }
        }
    }

    func exportLog() {
        FilePickerService.saveText(suggestedName: "Smelt_Log.txt") { url in
            guard let url else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            var blob = "=== SMELT DIAGNOSTIC LOG ===\n"
            blob += "Date: \(formatter.string(from: Date()))\n"
            blob += "macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            blob += "App Version: \(AppInfo.version)\n"
            blob += "Global Target Format: \(self.settings.globalFormat.rawValue)\n"
            blob += "Output Mode: \(self.settings.mode == .same ? "Same Directory" : "Custom Folder")\n"
            blob += "File Count: \(self.files.count)\n"
            blob += "----------------------------\n"

            for file in self.files {
                blob += "File: \(file.name)\n"
                blob += "Size: \(file.size)\n"
                blob += "Format: \(file.ext)\n"
                blob += "State: \(file.state)\n"
                blob += "Title ID: \(file.titleID ?? "N/A")\n"
                blob += "Product Code: \(file.productCode ?? "N/A")\n"
                blob += "----------------------------\n"
            }

            blob += "CONSOLE OUTPUT:\n\n"
            blob += self.console
            try? blob.write(to: url, atomically: true, encoding: .utf8)
            self.log("Diagnostic log saved to \(url.lastPathComponent)")
        }
    }

    private func setProgress(id: UUID, _ value: Double) {
        DispatchQueue.main.async {
            self.update(id: id) { $0.progress = value }
        }
    }

    private func update(id: UUID, _ mutate: (inout ROM) -> Void) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        var copy = files[index]
        mutate(&copy)
        files[index] = copy
    }
}
