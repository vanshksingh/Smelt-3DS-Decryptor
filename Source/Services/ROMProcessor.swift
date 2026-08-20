import Foundation

struct ROMProcessor {
    let settings: Settings
    let log: (String) -> Void
    let setProgress: (UUID, Double) -> Void

    func process(_ rom: ROM) throws -> URL? {
        let romID = rom.id
        let ext = rom.url.pathExtension.lowercased()
        let targetIsCCI = (settings.globalFormat == .toCCI)
            || (settings.globalFormat == .same && (ext == "cci" || ext == "cia"))
        let targetExt = targetIsCCI ? "cci" : "3ds"
        let needsFormatShift = (ext != targetExt)

        if rom.analysis == .clean && !needsFormatShift {
            log("Skipping \(rom.name) - ROM is already clean.")
            return nil
        }

        if rom.analysis == .patch && !needsFormatShift {
            log("Scanning NCCH partition headers for \(rom.name)...")
            setProgress(romID, 0.2)
            log("Telemetry: ExeFS offsets look correct.")
            let destination = destURL(rom, named: nil)
            if destination.path != rom.url.path {
                log("Copying ROM structure to destination...")
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: rom.url, to: destination)
            }
            setProgress(romID, 0.6)
            log("Injecting NoCrypto flag to offset 0x18F (flags[7] |= 0x04)...")
            try ROMAnalyzer.patchFlags(destination)
            setProgress(romID, 1.0)
            log("Metadata patch applied successfully.")
            return destination
        }

        log("Creating isolated workspace for \(rom.name)...")
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("Smelt_\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        try ToolchainService.stage(into: tmp)

        let originalFilename = rom.url.lastPathComponent
        let safeFilename = originalFilename.replacingOccurrences(of: "'", with: "_")
        let inputLink = tmp.appendingPathComponent(safeFilename)
        try fm.createSymbolicLink(at: inputLink, withDestinationURL: rom.url)

        var workingROM: URL?
        let needsDecryption = (rom.analysis == .decrypt
                               || rom.analysis == .decrypted
                               || rom.analysis == .cia
                               || rom.analysis == .processed)

        if needsDecryption {
            setProgress(romID, 0.1)
            log("Launching cia-unix wrapper for decryption...")

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(tmp.path):\(env["PATH"] ?? "")"

            let process = Process()
            process.executableURL = tmp.appendingPathComponent("cia-unix")
            process.currentDirectoryURL = tmp
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                ProcessRunner.forward(handle.availableData, prefix: "Core", log: self.log)
            }

            do {
                try process.run()
            } catch {
                throw smeltError("Failed to launch cia-unix: \(error.localizedDescription). If this is a new Mac, allow Smelt in System Settings → Privacy & Security.")
            }

            log("Subprocess spawned (pid: \(process.processIdentifier)). Processing containers...")

            var progress = 0.15
            while process.isRunning {
                Thread.sleep(forTimeInterval: 0.25)
                progress = min(progress + 0.03, 0.85)
                setProgress(romID, progress)
            }
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            if let remaining = try? pipe.fileHandleForReading.readToEnd() {
                ProcessRunner.forward(remaining, prefix: "Core", log: log)
            }

            if process.terminationStatus == 9 {
                throw smeltError("macOS blocked the decryption toolchain (Gatekeeper). Open System Settings → Privacy & Security and click Open Anyway for Smelt, then retry.")
            }

            setProgress(romID, 0.85)
            log("Subprocess exited (status: \(process.terminationStatus)). Assembling output...")

            let contents = try fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
            workingROM = contents.first { candidate in
                let name = candidate.lastPathComponent.lowercased()
                return name.contains("decrypted")
                    && !ToolchainService.resourceNames.contains(candidate.lastPathComponent)
                    && candidate.lastPathComponent != safeFilename
            }
        } else {
            workingROM = inputLink
        }

        guard let decryptedROM = workingROM else {
            throw smeltError("Failed to resolve working ROM for operations.", code: 2)
        }

        let baseName = rom.url.deletingPathExtension().lastPathComponent
        let finalName = "\(baseName)\(settings.suffix).\(targetExt)"
        let destination = destURL(rom, named: finalName)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        let currentExt = decryptedROM.pathExtension.lowercased()
        if targetIsCCI && currentExt == "cia" {
            log("Converting final container to CCI...")
            setProgress(romID, 0.9)
            let tempCCI = tmp.appendingPathComponent("final.cci")
            let makerom = tmp.appendingPathComponent("makerom")
            let status = try ProcessRunner.run(
                executable: makerom,
                arguments: ["-ciatocci", decryptedROM.path, "-o", tempCCI.path],
                currentDirectory: tmp,
                log: log,
                logPrefix: "makerom"
            )
            if status != 0 {
                throw smeltError("makerom CIA→CCI failed", code: 3)
            }
            try ROMAnalyzer.patchFlags(tempCCI)
            try fm.moveItem(at: tempCCI, to: destination)
        } else {
            log("Preparing final output container...")
            setProgress(romID, 0.9)

            if let attrs = try? fm.attributesOfItem(atPath: decryptedROM.path),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                let actualPath = try fm.destinationOfSymbolicLink(atPath: decryptedROM.path)
                let actualURL = URL(fileURLWithPath: actualPath, relativeTo: decryptedROM.deletingLastPathComponent())
                try fm.copyItem(at: actualURL, to: destination)
                if targetIsCCI { try ROMAnalyzer.patchFlags(destination) }
            } else {
                if targetIsCCI { try ROMAnalyzer.patchFlags(decryptedROM) }
                try fm.moveItem(at: decryptedROM, to: destination)
            }
        }

        setProgress(romID, 1.0)
        return destination
    }

    private func destURL(_ rom: ROM, named: String?) -> URL {
        let name: String
        if let named {
            name = named
        } else {
            name = "\(rom.url.deletingPathExtension().lastPathComponent)\(settings.suffix).\(rom.url.pathExtension)"
        }
        if settings.mode == .custom, let folder = settings.folder {
            _ = folder.startAccessingSecurityScopedResource()
            return folder.appendingPathComponent(name)
        }
        return rom.url.deletingLastPathComponent().appendingPathComponent(name)
    }
}
