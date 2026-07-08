import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Palette
let BG   = Color(red:0.05,green:0.05,blue:0.08)
let SIDE = Color(red:0.04,green:0.04,blue:0.065)
let CARD = Color.white.opacity(0.05)
let BLU  = Color(red:0.18,green:0.72,blue:1.0)
let PRP  = Color(red:0.65,green:0.38,blue:1.0)
let GRN  = Color(red:0.25,green:0.88,blue:0.55)
let ORG  = Color(red:1.0,green:0.65,blue:0.15)
let RED  = Color(red:1.0,green:0.35,blue:0.4)
let BRD  = Color.white.opacity(0.08)

// MARK: - ROM Analysis
enum Analysis: String {
    case unknown="Scanning", clean="Already Clean", patch="Needs Flag Patch"
    case decrypt="Needs Decrypt", invalid="Invalid", cia="CIA File"
    case patched="Flags Patched", decrypted="Decrypted", processed="Processed"
    
    var col: Color { switch self {
        case .clean, .patched, .decrypted, .processed: return GRN
        case .patch: return ORG
        case .decrypt: return BLU
        case .cia: return PRP
        case .invalid: return RED
        default: return .gray } }
        
    var icon: String { switch self {
        case .clean, .patched, .decrypted, .processed: return "checkmark.shield.fill"
        case .patch: return "wrench.and.screwdriver.fill"
        case .decrypt: return "lock.fill"
        case .cia: return "doc.badge.arrow.up.fill"
        case .invalid: return "exclamationmark.triangle.fill"
        default: return "ellipsis.circle" } }
}

// MARK: - ROM State
enum RState: Equatable {
    case queued, scanning, running, done, failed, skipped
    var label: String { switch self {
        case .queued:"Queued"; case .scanning:"Scanning"; case .running:"Processing"
        case .done:"Done"; case .failed:"Failed"; case .skipped:"Skipped" } }
    var col: Color { switch self {
        case .queued:ORG; case .scanning:BLU.opacity(0.7); case .running:BLU
        case .done:GRN; case .failed:RED; case .skipped:.gray } }
}

enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case same = "Same as Input (CCI Fallback)"
    case to3DS = "Convert to 3DS"
    case toCCI = "Convert to CCI"
    
    var id: String { self.rawValue }
}

// MARK: - Model
struct ROM: Identifiable, Equatable {
    let id=UUID(); let url:URL; let name:String; let ext:String; let size:String
    var state:RState = .queued; var analysis:Analysis = .unknown
    var progress:Double=0; var note:String=""; var outputURL:URL?=nil
    var logs:[String]=[]
    
    // Metadata properties
    var titleID: String? = nil
    var productCode: String? = nil
    
    func expectedOutputExt(globalFormat: OutputFormat) -> String {
        switch globalFormat {
        case .same:
            return ext.uppercased() == "CIA" ? "CCI" : ext
        case .to3DS:
            return "3DS"
        case .toCCI:
            return "CCI"
        }
    }
    
    static func==(a:ROM,b:ROM)->Bool{a.id==b.id}
}


// MARK: - Settings
class Settings: ObservableObject {
    enum OutMode: String, CaseIterable { case same="Same as Source"; case custom="Custom Folder" }
    @Published var mode:OutMode = .same
    @Published var folder:URL? = nil
    @Published var suffix:String = " Decrypted"
    @Published var autoOpen:Bool = false
    @Published var showConsole:Bool = false
    @Published var globalFormat: OutputFormat = .same
}

// MARK: - AppState
class AppState: ObservableObject {
    @Published var files:[ROM]=[]
    @Published var busy=false
    @Published var console=""
    @Published var showKeys=false
    let settings=Settings()

    // Add multiple URLs safely on a background thread
    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var filesToAdd: [ROM] = []
            
            for url in urls {
                var d: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &d) else { continue }
                
                if d.boolValue {
                    guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
                    for case let u as URL in e {
                        if let rom = self.prepareROM(u) {
                            filesToAdd.append(rom)
                        }
                    }
                } else {
                    if let rom = self.prepareROM(url) {
                        filesToAdd.append(rom)
                    }
                }
            }
            
            DispatchQueue.main.async {
                var newROMs: [ROM] = []
                for rom in filesToAdd {
                    if !self.files.contains(where: { $0.url == rom.url }) {
                        newROMs.append(rom)
                    }
                }
                
                guard !newROMs.isEmpty else { return }
                
                let startIdx = self.files.count
                self.files.append(contentsOf: newROMs)
                
                // Trigger analysis scans
                for (offset, rom) in newROMs.enumerated() {
                    self.scan(romID: rom.id, index: startIdx + offset)
                }
                self.badge()
            }
        }
    }
    
    private func prepareROM(_ url: URL) -> ROM? {
        let ext = url.pathExtension.lowercased()
        guard ["3ds", "cia", "cci", "cxi"].contains(ext) else { return nil }
        
        let sz = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
        
        var r = ROM(url: url, name: url.lastPathComponent, ext: ext.uppercased(), size: sizeStr)
        if ext == "cia" {
            r.analysis = .cia
            r.state = .queued
        }
        return r
    }

    // Pre-flight scan
    func scan(romID: UUID, index: Int) {
        guard index < files.count, files[index].id == romID else { return }
        files[index].state = .scanning
        let url = files[index].url
        
        DispatchQueue.global(qos: .utility).async {
            let a = self.analyze(url)
            
            // Fast Swift-based metadata parsing
            let swiftMeta = self.extractSwiftMetadata(url)
            
            DispatchQueue.main.async {
                if let i = self.files.firstIndex(where: { $0.id == romID }) {
                    self.files[i].analysis = a
                    if let tid = swiftMeta.titleID { self.files[i].titleID = tid }
                    if let pc = swiftMeta.productCode { self.files[i].productCode = pc }
                    
                    if a == .clean {
                        self.files[i].state = .done
                        self.files[i].note = "Already fully decrypted"
                    } else {
                        self.files[i].state = .queued
                    }
                    self.badge()
                }
            }
        }
    }
    
    private func extractSwiftMetadata(_ url: URL) -> (titleID: String?, productCode: String?) {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return (nil, nil) }
        defer { try? fh.close() }
        
        let fileLen = (try? fh.seekToEnd()) ?? 0
        guard fileLen > 0x1000 else { return (nil, nil) }
        
        let ext = url.pathExtension.lowercased()
        var po: UInt64 = 0
        var titleIDStr: String? = nil
        
        if ext == "cia" {
            guard let _ = try? fh.seek(toOffset: 0),
                  let head = try? fh.read(upToCount: 0x20), head.count == 0x20 else { return (nil, nil) }
            
            let certSz = readUInt32Le(from: head, offset: 8) ?? 0
            let tikSz = readUInt32Le(from: head, offset: 12) ?? 0
            
            let align = { (val: UInt64) -> UInt64 in
                return (val + 63) & ~63
            }
            
            let certOff = align(0x20)
            let tikOff = align(certOff + UInt64(certSz))
            let tmdOff = align(tikOff + UInt64(tikSz))
            
            guard let _ = try? fh.seek(toOffset: tmdOff + 0x18C),
                  let tIDBytes = try? fh.read(upToCount: 8), tIDBytes.count == 8 else { return (nil, nil) }
            
            titleIDStr = tIDBytes.map { String(format: "%02X", $0) }.joined()
            
            let tmdSz = readUInt32Le(from: head, offset: 16) ?? 0
            let contentOff = align(tmdOff + UInt64(tmdSz))
            po = contentOff
        } else {
            guard let _ = try? fh.seek(toOffset: 0x120),
                  let pt = try? fh.read(upToCount: 64), pt.count == 64 else { return (nil, nil) }
            guard let sec = readUInt32Le(from: pt, offset: 0), sec > 0 else { return (nil, nil) }
            po = UInt64(sec) * 0x200
        }
        
        guard let _ = try? fh.seek(toOffset: po + 0x100),
              let ncchHead = try? fh.read(upToCount: 0x200), ncchHead.count == 0x200 else {
            if ext == "cia" {
                return (titleIDStr, "CTR-N-CIA")
            }
            return (nil, nil)
        }
        
        guard ncchHead[0..<4] == Data([78, 67, 67, 72]) else {
            if ext == "cia" {
                return (titleIDStr, "CTR-N-CIA")
            }
            return (nil, nil)
        }
        
        let tIDBytes = ncchHead[0x18..<0x20]
        titleIDStr = tIDBytes.reversed().map { String(format: "%02X", $0) }.joined()
        
        let prodBytes = ncchHead[0x50..<0x60]
        let productCodeStr = String(data: prodBytes.prefix(while: { $0 != 0 }), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        return (titleIDStr, productCodeStr)
    }
    
    private func analyze(_ url:URL) -> Analysis {
        if url.pathExtension.lowercased() == "cia" {
            return .cia
        }
        guard let fh=try? FileHandle(forReadingFrom:url) else{return .invalid}
        defer{try? fh.close()}
        guard let _=try? fh.seek(toOffset:0x120),
              let pt=try? fh.read(upToCount:64), pt.count==64 else{return .invalid}
        guard let sec = readUInt32Le(from: pt, offset: 0), sec > 0 else { return .invalid }
        let po=UInt64(sec)*0x200
        guard let _=try? fh.seek(toOffset:po+0x100),
              let mg=try? fh.read(upToCount:4),
              mg==Data([78,67,67,72]) else{return .invalid}
        guard let _=try? fh.seek(toOffset:po+0x188),
              let fl=try? fh.read(upToCount:8), fl.count==8 else{return .invalid}
        let noCrypto=fl[7] & 0x04 != 0
        let us:UInt64 = fl.count>6 ? 512*UInt64(1<<fl[6]) : 512
        guard let _=try? fh.seek(toOffset:po+0x1A0),
              let eo=try? fh.read(upToCount:4), eo.count==4 else{return noCrypto ? .clean : .decrypt}
        guard let eoVal = readUInt32Le(from: eo, offset: 0) else { return noCrypto ? .clean : .decrypt }
        let exOff=po+UInt64(eoVal)*us
        guard let _=try? fh.seek(toOffset:exOff),
              let hd=try? fh.read(upToCount:8), hd.count==8 else{return noCrypto ? .clean : .decrypt}
        let printable=hd.allSatisfy{($0>=0x20 && $0<0x7F)||$0==0}
        if printable { return noCrypto ? .clean : .patch }
        return .decrypt
    }
    
    // Queue management
    func remove(_ r:ROM){ files.removeAll{$0.id==r.id}; badge() }
    func clearAll()      { guard !busy else{return}; files.removeAll(); badge() }
    func clearDone()     { guard !busy else{return}; files.removeAll{$0.state == .done || $0.state == .skipped}; badge() }
    
    func bindingFor(_ romID: UUID) -> Binding<ROM> {
        Binding(
            get: {
                self.files.first(where: { $0.id == romID }) ?? ROM(url: URL(fileURLWithPath: ""), name: "", ext: "", size: "")
            },
            set: { newValue in
                if let idx = self.files.firstIndex(where: { $0.id == romID }) {
                    self.files[idx] = newValue
                }
            }
        )
    }
    
    func requeueIfNeeded(for format: OutputFormat) {
        for i in files.indices {
            let expectedExt = files[i].expectedOutputExt(globalFormat: format)
            let currentExt = files[i].outputURL?.pathExtension.lowercased() ?? files[i].ext.lowercased()
            
            if currentExt != expectedExt.lowercased() {
                files[i].state = .queued
                files[i].note = ""
                files[i].progress = 0
            }
        }
        badge()
    }
    
    func log(_ m:String) {
        let t={ let f=DateFormatter(); f.dateFormat="HH:mm:ss"; return f.string(from:Date()) }()
        DispatchQueue.main.async { self.console += "[\(t)] \(m)\n" }
    }
    
    func badge() {
        let n=files.filter{$0.state == .queued || $0.state == .running}.count
        DispatchQueue.main.async { NSApplication.shared.dockTile.badgeLabel = n>0 ? "\(n)" : nil }
    }
    
    // Run queue processing
    func run() {
        guard !busy else{return}
        let pending=files.filter{$0.state == .queued || $0.state == .failed}
        guard !pending.isEmpty else{return}
        busy=true
        
        for i in files.indices where files[i].state == .failed {
            files[i].state = .queued
            files[i].note = ""
            files[i].logs = []
        }
        
        log("Batch processing started - targeting \(pending.count) ROM container(s)")
        
        let romsToProcess = pending
        
        DispatchQueue.global(qos:.userInitiated).async {
            for rom in romsToProcess {
                let romID = rom.id
                
                DispatchQueue.main.async {
                    if let i = self.files.firstIndex(where: { $0.id == romID }) {
                        self.files[i].state = .running
                        self.files[i].progress = 0
                    }
                    self.badge()
                }
                
                self.log("Initializing operation for \(rom.name)...")
                let startTime = Date()
                do {
                    let out = try self.process(rom)
                    let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))
                    
                    if let out = out {
                        let swiftMeta = self.extractSwiftMetadata(out)
                        DispatchQueue.main.async {
                            if let i = self.files.firstIndex(where: { $0.id == romID }) {
                                if let tid = swiftMeta.titleID { self.files[i].titleID = tid }
                                if let pc = swiftMeta.productCode { self.files[i].productCode = pc }
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        if let i = self.files.firstIndex(where: { $0.id == romID }) {
                            self.files[i].state = .done
                            self.files[i].outputURL = out
                            self.files[i].note = out?.lastPathComponent ?? ""
                            self.files[i].progress = 1.0
                            
                            // Transition state to completed status
                            if self.files[i].analysis == .patch {
                                self.files[i].analysis = .patched
                            } else if self.files[i].analysis == .decrypt {
                                self.files[i].analysis = .decrypted
                            } else if self.files[i].analysis == .cia {
                                self.files[i].analysis = .processed
                            }
                        }
                        self.badge()
                    }
                    self.log("Successfully processed \(rom.name) in \(elapsed)s")
                } catch {
                    DispatchQueue.main.async {
                        if let i = self.files.firstIndex(where: { $0.id == romID }) {
                            self.files[i].state = .failed
                            self.files[i].note = error.localizedDescription
                            self.files[i].logs.append(error.localizedDescription)
                        }
                        self.badge()
                    }
                    self.log("Failed on \(rom.name): \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.busy=false
                self.badge()
                self.log("Batch process complete.")
                if self.settings.autoOpen,
                   let f=self.files.compactMap({$0.outputURL?.deletingLastPathComponent()}).first {
                    NSWorkspace.shared.open(f)
                }
            }
        }
    }
    
    private func setP(id: UUID, _ v: Double) {
        DispatchQueue.main.async {
            if let i = self.files.firstIndex(where: { $0.id == id }) {
                self.files[i].progress = v
            }
        }
    }
    
    func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Smelt_Log.txt"
        
        if panel.runModal() == .OK, let url = panel.url {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            var logBlob = "=== SMELT DIAGNOSTIC LOG ===\n"
            logBlob += "Date: \(df.string(from: Date()))\n"
            logBlob += "macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            logBlob += "Global Target Format: \(settings.globalFormat.rawValue)\n"
            logBlob += "Output Mode: \(settings.mode == .same ? "Same Directory" : "Custom Folder")\n"
            logBlob += "File Count: \(files.count)\n"
            logBlob += "----------------------------\n"
            
            for file in files {
                logBlob += "File: \(file.name)\n"
                logBlob += "Size: \(file.size)\n"
                logBlob += "Format: \(file.ext)\n"
                logBlob += "State: \(file.state)\n"
                logBlob += "Title ID: \(file.titleID ?? "N/A")\n"
                logBlob += "Product Code: \(file.productCode ?? "N/A")\n"
                logBlob += "----------------------------\n"
            }
            
            logBlob += "CONSOLE OUTPUT:\n\n"
            logBlob += console
            
            try? logBlob.write(to: url, atomically: true, encoding: .utf8)
            self.log("Diagnostic log saved to \(url.lastPathComponent)")
        }
    }
    
    private func destURL(_ f:ROM, named:String?) -> URL {
        let nm:String
        if let n=named { nm=n }
        else { nm="\(f.url.deletingPathExtension().lastPathComponent)\(settings.suffix).\(f.url.pathExtension)" }
        if settings.mode == .custom, let fd=settings.folder { return fd.appendingPathComponent(nm) }
        return f.url.deletingLastPathComponent().appendingPathComponent(nm)
    }
    
    private func process(_ f:ROM) throws -> URL? {
        let romID = f.id
        let ext = f.url.pathExtension.lowercased()
        let sourceIsCIA = (ext == "cia")
        
        // Determine final target format (CIA vs 3DS vs CCI)
        let targetIsCCI = (settings.globalFormat == .toCCI) || (settings.globalFormat == .same && (ext == "cci" || ext == "cia"))
        let targetExt = targetIsCCI ? "cci" : "3ds"
        let needsFormatShift = (ext != targetExt)
        
        // If already clean and doesn't need format shifting, skip
        if f.analysis == .clean && !needsFormatShift {
            DispatchQueue.main.async {
                if let i = self.files.firstIndex(where: { $0.id == romID }) {
                    self.files[i].state = .skipped
                }
            }
            self.log("Skipping \(f.name) - ROM is already clean.")
            return nil
        }
        
        // If it only needs a flag patch and doesn't need format shifting, patch it in-place
        if f.analysis == .patch && !needsFormatShift {
            self.log("Scanning NCCH partition headers for \(f.name)...")
            setP(id: romID, 0.2)
            self.log("Telemetry: ExeFS offsets look correct.")
            let dst=destURL(f,named:nil)
            if dst.path != f.url.path {
                self.log("Copying ROM structure to destination...")
                if FileManager.default.fileExists(atPath:dst.path){try FileManager.default.removeItem(at:dst)}
                try FileManager.default.copyItem(at:f.url,to:dst)
            }
            setP(id: romID, 0.6)
            self.log("Injecting NoCrypto flag to offset 0x18F (flags[7] |= 0x04)...")
            try patchFlags(dst)
            setP(id: romID, 1.0)
            self.log("Metadata patch applied successfully.")
            return dst
        }
        
        // For everything else: Decryption and/or Format Shifting
        self.log("Creating isolated workspace for \(f.name)...")
        let fm=FileManager.default
        let tmp=fm.temporaryDirectory.appendingPathComponent("Smelt_\(UUID().uuidString)")
        try fm.createDirectory(at:tmp,withIntermediateDirectories:true)
        defer{try? fm.removeItem(at:tmp)}
        
        let deps=["cia-unix","ctrdecrypt","ctrtool","makerom","seeddb.bin"]
        for d in deps {
            guard let src=Bundle.main.url(forResource:d,withExtension:nil) else{
                throw NSError(domain:"Smelt",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing dependency: \(d)"])}
            try fm.createSymbolicLink(at:tmp.appendingPathComponent(d),withDestinationURL:src)
        }
        
        let originalFilename = f.url.lastPathComponent
        let safeFilename = originalFilename.replacingOccurrences(of: "'", with: "_")
        let inputFilename = safeFilename
        let inputLink = tmp.appendingPathComponent(inputFilename)
        try fm.createSymbolicLink(at:inputLink,withDestinationURL:f.url)
        
        var working3DSRom: URL? = nil
        
        // Step 1: Handle decryption if needed
        let needsDecryption = (f.analysis == .decrypt || f.analysis == .decrypted || f.analysis == .cia || f.analysis == .processed)
        let isCIA = (f.analysis == .cia || f.analysis == .processed)
        
        if needsDecryption {
            setP(id: romID, 0.1)
            
            let p=Process()
            self.log("Launching cia-unix wrapper script for decryption...")
            p.executableURL=tmp.appendingPathComponent("cia-unix")
            p.currentDirectoryURL=tmp
            
            var env=ProcessInfo.processInfo.environment
            env["PATH"]="\(tmp.path):\(env["PATH"] ?? "")"
            p.environment=env
            
            let pipe=Pipe()
            p.standardOutput=pipe
            p.standardError=pipe
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    let cleanedStr = str.replacingOccurrences(of: "\r", with: "\n")
                    let lines = cleanedStr.split(separator: "\n")
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            self.log("[Core] \(trimmed)")
                        }
                    }
                }
            }
            
            try p.run()
            self.log("Subprocess spawned (pid: \(p.processIdentifier)). Processing containers...")
            
            var pg=0.15
            while p.isRunning {
                Thread.sleep(forTimeInterval:0.25)
                pg=min(pg+0.03,0.85)
                setP(id: romID, pg)
            }
            p.waitUntilExit()
            
            pipe.fileHandleForReading.readabilityHandler = nil
            if let remaining = try? pipe.fileHandleForReading.readToEnd(), !remaining.isEmpty {
                if let str = String(data: remaining, encoding: .utf8), !str.isEmpty {
                    let cleanedStr = str.replacingOccurrences(of: "\r", with: "\n")
                    for line in cleanedStr.split(separator: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            self.log("[Core] \(trimmed)")
                        }
                    }
                }
            }
            
            setP(id: romID, 0.85)
            self.log("Subprocess exited (status: \(p.terminationStatus)). Assembling output...")
            
            let contents=try fm.contentsOfDirectory(at:tmp,includingPropertiesForKeys:nil)
            if let dec=contents.first(where:{c in
                let n=c.lastPathComponent.lowercased()
                return n.contains("decrypted") && !deps.contains(c.lastPathComponent) && c.lastPathComponent != inputFilename
            }) {
                working3DSRom = dec
            }
        } else {
            // Already clean/patched but needs format shifting
            working3DSRom = inputLink
        }
        guard let decrypted3DS = working3DSRom else {
            throw NSError(domain:"Smelt", code:2, userInfo:[NSLocalizedDescriptionKey:"Failed to resolve working ROM for operations."])
        }
        
        // 3. Format Shift to Target if needed
        let baseName = f.url.deletingPathExtension().lastPathComponent
        let finalName = "\(baseName)\(settings.suffix).\(targetExt)"
        let dst = destURL(f, named: finalName)
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        
        let currentExt = decrypted3DS.pathExtension.lowercased()
        
        if targetIsCCI && currentExt == "cia" {
            self.log("Converting final container to CCI...")
            setP(id: romID, 0.9)
            let tempCci = tmp.appendingPathComponent("final.cci")
            guard let makeromURL = Bundle.main.url(forResource: "makerom", withExtension: nil) else {
                throw NSError(domain: "Smelt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing makerom dependency"])
            }
            let status = try runProcess(executable: makeromURL, args: ["-ciatocci", decrypted3DS.path, "-o", tempCci.path], currentDirectory: tmp, logPrefix: "makerom")
            if status != 0 { throw NSError(domain: "Smelt", code: 3, userInfo: [NSLocalizedDescriptionKey: "makerom CIA->CCI failed"]) }
            try patchFlags(tempCci)
            try fm.moveItem(at: tempCci, to: dst)
        } else {
            // No format shift needed, just move the current file
            self.log("Preparing final output container...")
            setP(id: romID, 0.9)
            
            if let attrs = try? fm.attributesOfItem(atPath: decrypted3DS.path), attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                let actualPath = try fm.destinationOfSymbolicLink(atPath: decrypted3DS.path)
                let actualURL = URL(fileURLWithPath: actualPath, relativeTo: decrypted3DS.deletingLastPathComponent())
                try fm.copyItem(at: actualURL, to: dst)
                if targetIsCCI { try patchFlags(dst) }
            } else {
                if targetIsCCI { try patchFlags(decrypted3DS) }
                try fm.moveItem(at: decrypted3DS, to: dst)
            }
        }
        
        setP(id: romID, 1.0)
        return dst
    }
    
    @discardableResult
    private func runProcess(executable: URL, args: [String], currentDirectory: URL, logPrefix: String? = nil) throws -> Int32 {
        let p = Process()
        p.executableURL = executable
        p.arguments = args
        p.currentDirectoryURL = currentDirectory
        
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        
        if let logPrefix = logPrefix {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    let cleanedStr = str.replacingOccurrences(of: "\r", with: "\n")
                    for line in cleanedStr.split(separator: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            self.log("[\(logPrefix)] \(trimmed)")
                        }
                    }
                }
            }
        }
        
        try p.run()
        p.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        return p.terminationStatus
    }
    
    @discardableResult
    private func patchFlags(_ url:URL) throws -> Bool {
        let fh=try FileHandle(forUpdating:url); defer{try? fh.close()}
        try fh.seek(toOffset:0x120)
        guard let pt=try fh.read(upToCount:64), pt.count==64 else{return false}
        var patched=false
        for p in 0..<8 {
            guard let s = readUInt32Le(from: pt, offset: p * 8) else { continue }
            if s==0{continue}
            let po=UInt64(s)*0x200
            try fh.seek(toOffset:po+0x100)
            guard let mg=try fh.read(upToCount:4), mg==Data([78,67,67,72]) else{continue}
            try fh.seek(toOffset:po+0x188)
            guard var fl=try fh.read(upToCount:8).map({[UInt8]($0)}), fl.count==8 else{continue}
            if fl[7] & 0x04==0 { fl[7] |= 0x04; try fh.seek(toOffset:po+0x188); try fh.write(contentsOf:Data(fl)); patched=true }
        }
        return patched
    }
    
    private func readUInt32Le(from data: Data, offset: Int = 0) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else { return nil }
        let idx = data.startIndex + offset
        return UInt32(data[idx]) |
               (UInt32(data[idx + 1]) << 8) |
               (UInt32(data[idx + 2]) << 16) |
               (UInt32(data[idx + 3]) << 24)
    }
}
