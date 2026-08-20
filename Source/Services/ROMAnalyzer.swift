import Foundation

enum ROMAnalyzer {
    /// CIA cert/ticket/TMD plus NCCH header should sit well below this.
    private static let maxContainerHeader: UInt64 = 32 * 1024 * 1024

    static func analyze(_ url: URL) -> Analysis {
        if url.pathExtension.lowercased() == "cia" {
            return .cia
        }

        guard let file = HeaderFile(url: url) else { return .invalid }
        defer { file.close() }

        guard let partitionTable = file.read(0x120, 64), partitionTable.count == 64 else { return .invalid }
        guard let sector = readUInt32Le(from: partitionTable, offset: 0), sector > 0 else { return .invalid }
        guard let partitionOffset = multiplied(UInt64(sector), 0x200), partitionOffset < file.size else {
            return .invalid
        }

        guard let magic = file.read(partitionOffset + 0x100, 4),
              magic == Data([78, 67, 67, 72]) else { return .invalid }
        guard let flags = file.read(partitionOffset + 0x188, 8), flags.count == 8 else { return .invalid }

        let noCrypto = flags[7] & 0x04 != 0
        let shift = min(UInt64(flags[6]), 16)
        let mediaUnit: UInt64 = 512 * (UInt64(1) << shift)

        guard let exHeaderOffsetBytes = file.read(partitionOffset + 0x1A0, 4),
              exHeaderOffsetBytes.count == 4,
              let exHeaderUnits = readUInt32Le(from: exHeaderOffsetBytes, offset: 0),
              let exHeaderOffset = multiplied(UInt64(exHeaderUnits), mediaUnit).map({ partitionOffset + $0 }),
              let header = file.read(exHeaderOffset, 8),
              header.count == 8 else {
            return noCrypto ? .clean : .decrypt
        }

        let printable = header.allSatisfy { ($0 >= 0x20 && $0 < 0x7F) || $0 == 0 }
        if printable { return noCrypto ? .clean : .patch }
        return .decrypt
    }

    static func extractMetadata(_ url: URL) -> (titleID: String?, productCode: String?) {
        guard let file = HeaderFile(url: url) else { return (nil, nil) }
        defer { file.close() }
        guard file.size > 0x1000 else { return (nil, nil) }

        let ext = url.pathExtension.lowercased()
        var partitionOffset: UInt64 = 0
        var titleID: String?

        if ext == "cia" {
            guard let head = file.read(0, 0x20), head.count == 0x20 else { return (nil, nil) }

            let certSize = UInt64(readUInt32Le(from: head, offset: 8) ?? 0)
            let ticketSize = UInt64(readUInt32Le(from: head, offset: 12) ?? 0)
            let tmdSize = UInt64(readUInt32Le(from: head, offset: 16) ?? 0)
            let align: (UInt64) -> UInt64 = { ($0 + 63) & ~63 }

            guard certSize <= maxContainerHeader,
                  ticketSize <= maxContainerHeader,
                  tmdSize <= maxContainerHeader else {
                return (nil, nil)
            }

            let certOff = align(0x20)
            let ticketOff = align(certOff + certSize)
            let tmdOff = align(ticketOff + ticketSize)
            guard tmdOff + 0x194 <= file.size, tmdOff <= maxContainerHeader else { return (nil, nil) }

            guard let tIDBytes = file.read(tmdOff + 0x18C, 8), tIDBytes.count == 8 else { return (nil, nil) }
            titleID = tIDBytes.map { String(format: "%02X", $0) }.joined()

            partitionOffset = align(tmdOff + tmdSize)
            guard partitionOffset < file.size else { return (titleID, "CTR-N-CIA") }
        } else {
            guard let partitionTable = file.read(0x120, 64), partitionTable.count == 64 else { return (nil, nil) }
            guard let sector = readUInt32Le(from: partitionTable, offset: 0), sector > 0 else { return (nil, nil) }
            guard let offset = multiplied(UInt64(sector), 0x200), offset < file.size else { return (nil, nil) }
            partitionOffset = offset
        }

        guard let ncchHead = file.read(partitionOffset + 0x100, 0x200), ncchHead.count == 0x200 else {
            return ext == "cia" ? (titleID, "CTR-N-CIA") : (nil, nil)
        }
        guard ncchHead[0..<4] == Data([78, 67, 67, 72]) else {
            return ext == "cia" ? (titleID, "CTR-N-CIA") : (nil, nil)
        }

        titleID = ncchHead[0x18..<0x20].reversed().map { String(format: "%02X", $0) }.joined()
        let productBytes = ncchHead[0x50..<0x60]
        let productCode = String(data: productBytes.prefix(while: { $0 != 0 }), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (titleID, productCode)
    }

    @discardableResult
    static func patchFlags(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0x120)
        guard let partitionTable = try handle.read(upToCount: 64), partitionTable.count == 64 else { return false }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        var patched = false
        for partition in 0..<8 {
            guard let sector = readUInt32Le(from: partitionTable, offset: partition * 8), sector != 0 else { continue }
            guard let offset = multiplied(UInt64(sector), 0x200), offset + 0x190 <= fileSize else { continue }
            try handle.seek(toOffset: offset + 0x100)
            guard let magic = try handle.read(upToCount: 4), magic == Data([78, 67, 67, 72]) else { continue }
            try handle.seek(toOffset: offset + 0x188)
            guard var flags = try handle.read(upToCount: 8).map({ [UInt8]($0) }), flags.count == 8 else { continue }
            if flags[7] & 0x04 == 0 {
                flags[7] |= 0x04
                try handle.seek(toOffset: offset + 0x188)
                try handle.write(contentsOf: Data(flags))
                patched = true
            }
        }
        return patched
    }

    static func readUInt32Le(from data: Data, offset: Int = 0) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else { return nil }
        let idx = data.startIndex + offset
        return UInt32(data[idx])
            | (UInt32(data[idx + 1]) << 8)
            | (UInt32(data[idx + 2]) << 16)
            | (UInt32(data[idx + 3]) << 24)
    }

    private static func multiplied(_ a: UInt64, _ b: UInt64) -> UInt64? {
        let (result, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow ? nil : result
    }
}

private struct HeaderFile {
    let handle: FileHandle
    let size: UInt64

    init?(url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileSizeKey,
            .isDirectoryKey
        ])
        if values?.isDirectory == true { return nil }

        let attributed = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let fromValues = UInt64(values?.fileSize ?? values?.totalFileSize ?? 0)
        let size = max(fromValues, attributed)
        guard size > 0 else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        guard let sample = try? handle.read(upToCount: 1), !sample.isEmpty else {
            try? handle.close()
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               status == .notDownloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            return nil
        }
        try? handle.seek(toOffset: 0)
        self.handle = handle
        self.size = size
    }

    func read(_ offset: UInt64, _ count: Int) -> Data? {
        guard count > 0, offset < size else { return nil }
        let available = min(UInt64(count), size - offset)
        guard available > 0, available <= UInt64(Int.max) else { return nil }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: Int(available))
        } catch {
            return nil
        }
    }

    func close() {
        try? handle.close()
    }
}
