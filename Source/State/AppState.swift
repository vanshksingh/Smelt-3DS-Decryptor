import SwiftUI
import AppKit

final class AppState: ObservableObject {
    @Published var files: [ROM] = []
    @Published var busy = false
    @Published var console = ""

    let settings = Settings()
    let scopedAccess = SecurityScopedAccess()

    private let scanQueue = DispatchQueue(label: "smelt.rom-scan", qos: .userInitiated, attributes: .concurrent)
    private let scanLimiter = DispatchSemaphore(value: 3)
    private var scanTokens: [UUID: UInt64] = [:]

    private static let maxROMsFromFolder = 2_000
    private static let scanTimeout: TimeInterval = 8

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
        files.filter { $0.state == .queued || $0.state == .failed || $0.state == .scanning }.count
    }

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        log("Importing \(urls.count) selected item(s)...")

        DispatchQueue.global(qos: .userInitiated).async {
            var prepared: [ROM] = []
            var skipped: [String] = []

            for url in urls {
                let normalized = ROMImport.normalize(url)

                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory)
                    || (try? normalized.checkResourceIsReachable()) == true

                guard exists else {
                    skipped.append("\(normalized.lastPathComponent) (\(ROMImport.Failure.notFound.description))")
                    continue
                }

                let isFolder = isDirectory.boolValue
                    || (try? normalized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

                if isFolder {
                    guard let enumerator = FileManager.default.enumerator(
                        at: normalized,
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isReadableKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else {
                        skipped.append("\(normalized.lastPathComponent) (folder unreadable)")
                        continue
                    }

                    var truncated = false
                    var foundInFolder = 0
                    for case let child as URL in enumerator {
                        if prepared.count >= Self.maxROMsFromFolder {
                            truncated = true
                            enumerator.skipDescendants()
                            break
                        }
                        guard ROMImport.isSupported(child) else { continue }
                        switch self.makeROM(from: child) {
                        case .success(let rom):
                            prepared.append(rom)
                            foundInFolder += 1
                        case .failure(let reason):
                            skipped.append("\(child.lastPathComponent) (\(reason.description))")
                        }
                    }
                    if foundInFolder == 0, !skipped.contains(where: { $0.hasPrefix(normalized.lastPathComponent) }) {
                        skipped.append("\(normalized.lastPathComponent) (no ROM files inside)")
                    }
                    if truncated {
                        DispatchQueue.main.async {
                            self.log("Stopped after \(Self.maxROMsFromFolder) ROMs in \(normalized.lastPathComponent). Add the rest separately.")
                        }
                    }
                    continue
                }

                switch self.makeROM(from: normalized) {
                case .success(let rom):
                    prepared.append(rom)
                case .failure(let reason):
                    skipped.append("\(normalized.lastPathComponent) (\(reason.description))")
                }
            }

            DispatchQueue.main.async {
                let existingPaths = Set(self.files.map(\.url.path))
                let newcomers = prepared.filter { !existingPaths.contains($0.url.path) }

                if !skipped.isEmpty {
                    self.log("Skipped: \(skipped.joined(separator: ", "))")
                }

                guard !newcomers.isEmpty else {
                    if prepared.isEmpty {
                        self.log("No .3ds, .cia, .cci, or .cxi files were found in that selection.")
                    } else {
                        self.log("Those ROMs are already in the queue.")
                    }
                    self.settings.showConsole = true
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

    private func makeROM(from url: URL) -> Result<ROM, ROMImport.Failure> {
        switch ROMImport.validateFile(url) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let (file, bytes)):
            let retained = scopedAccess.retain(file)
            let ext = retained.pathExtension.uppercased()
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            var rom = ROM(url: retained, name: retained.lastPathComponent, ext: ext, size: size)
            if ext.lowercased() == "cia" {
                rom.analysis = .cia
            }
            return .success(rom)
        }
    }

    func scan(romID: UUID) {
        guard let rom = files.first(where: { $0.id == romID }) else { return }
        let token = (scanTokens[romID] ?? 0) + 1
        scanTokens[romID] = token
        update(id: romID) { $0.state = .scanning }

        let url = rom.url
        let isCIA = rom.ext.lowercased() == "cia"

        scanQueue.async {
            self.scanLimiter.wait()

            let box = ScanBox(analysis: isCIA ? .cia : .decrypt)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                if !isCIA {
                    box.analysis = ROMAnalyzer.analyze(url)
                }
                let metadata = ROMAnalyzer.extractMetadata(url)
                box.titleID = metadata.titleID
                box.productCode = metadata.productCode
                group.leave()
            }

            let timedOut = group.wait(timeout: .now() + Self.scanTimeout) == .timedOut
            self.scanLimiter.signal()

            let analysis = timedOut ? (isCIA ? Analysis.cia : .decrypt) : box.analysis
            let titleID = timedOut ? nil : box.titleID
            let productCode = timedOut ? nil : box.productCode

            DispatchQueue.main.async {
                guard self.scanTokens[romID] == token else { return }
                self.scanTokens[romID] = nil
                self.applyScan(
                    romID: romID,
                    analysis: analysis,
                    titleID: titleID,
                    productCode: productCode,
                    timedOut: timedOut
                )
            }
        }
    }

    private func applyScan(
        romID: UUID,
        analysis: Analysis,
        titleID: String?,
        productCode: String?,
        timedOut: Bool
    ) {
        update(id: romID) { rom in
            rom.analysis = analysis
            if let titleID { rom.titleID = titleID }
            if let productCode { rom.productCode = productCode }
            if timedOut {
                rom.state = .queued
                rom.note = "Header scan timed out; queued for processing"
            } else if analysis == .clean {
                rom.state = .done
                rom.note = "Already fully decrypted"
            } else if analysis == .invalid {
                rom.state = .queued
                rom.note = "Could not read a valid NCCH header"
            } else {
                rom.state = .queued
            }
        }
        if timedOut, let name = files.first(where: { $0.id == romID })?.name {
            log("Header scan timed out for \(name); queued anyway.")
        }
        badge()
    }

    private func finalizeIncompleteScans() {
        for index in files.indices where files[index].state == .scanning {
            scanTokens[files[index].id] = nil
            if files[index].analysis == .unknown {
                files[index].analysis = files[index].ext.lowercased() == "cia" ? .cia : .decrypt
            }
            files[index].state = .queued
            if files[index].note.isEmpty {
                files[index].note = "Scan skipped; queued for processing"
            }
        }
    }

    func remove(_ rom: ROM) {
        scanTokens[rom.id] = nil
        files.removeAll { $0.id == rom.id }
        scopedAccess.release(rom.url)
        badge()
    }

    func clearAll() {
        guard !busy else { return }
        scanTokens.removeAll()
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
        var copy = files
        var changed = false
        for index in copy.indices {
            let expected = copy[index].expectedOutputExt(globalFormat: format)
            let current = copy[index].outputURL?.pathExtension.lowercased() ?? copy[index].ext.lowercased()
            if current != expected.lowercased() {
                copy[index].state = .queued
                copy[index].note = ""
                copy[index].progress = 0
                changed = true
            }
        }
        if changed {
            files = copy
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
        finalizeIncompleteScans()
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

private final class ScanBox {
    private let lock = NSLock()
    private var _analysis: Analysis
    private var _titleID: String?
    private var _productCode: String?

    init(analysis: Analysis) {
        self._analysis = analysis
    }

    var analysis: Analysis {
        get { lock.lock(); defer { lock.unlock() }; return _analysis }
        set { lock.lock(); _analysis = newValue; lock.unlock() }
    }

    var titleID: String? {
        get { lock.lock(); defer { lock.unlock() }; return _titleID }
        set { lock.lock(); _titleID = newValue; lock.unlock() }
    }

    var productCode: String? {
        get { lock.lock(); defer { lock.unlock() }; return _productCode }
        set { lock.lock(); _productCode = newValue; lock.unlock() }
    }
}
