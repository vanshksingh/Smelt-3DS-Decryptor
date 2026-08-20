import Foundation

enum ROMAnalyzer {
    static func analyze(_ url: URL) -> Analysis {
        if url.pathExtension.lowercased() == "cia" {
            return .cia
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .invalid }
        defer { try? handle.close() }

        guard let _ = try? handle.seek(toOffset: 0x120),
              let partitionTable = try? handle.read(upToCount: 64),
              partitionTable.count == 64 else { return .invalid }
        guard let sector = readUInt32Le(from: partitionTable, offset: 0), sector > 0 else { return .invalid }

        let partitionOffset = UInt64(sector) * 0x200
        guard let _ = try? handle.seek(toOffset: partitionOffset + 0x100),
              let magic = try? handle.read(upToCount: 4),
              magic == Data([78, 67, 67, 72]) else { return .invalid }
        guard let _ = try? handle.seek(toOffset: partitionOffset + 0x188),
              let flags = try? handle.read(upToCount: 8),
              flags.count == 8 else { return .invalid }

        let noCrypto = flags[7] & 0x04 != 0
        let mediaUnit: UInt64 = flags.count > 6 ? 512 * UInt64(1 << flags[6]) : 512

        guard let _ = try? handle.seek(toOffset: partitionOffset + 0x1A0),
              let exHeaderOffsetBytes = try? handle.read(upToCount: 4),
              exHeaderOffsetBytes.count == 4 else { return noCrypto ? .clean : .decrypt }
        guard let exHeaderUnits = readUInt32Le(from: exHeaderOffsetBytes, offset: 0) else {
            return noCrypto ? .clean : .decrypt
        }

        let exHeaderOffset = partitionOffset + UInt64(exHeaderUnits) * mediaUnit
        guard let _ = try? handle.seek(toOffset: exHeaderOffset),
              let header = try? handle.read(upToCount: 8),
              header.count == 8 else { return noCrypto ? .clean : .decrypt }

        let printable = header.allSatisfy { ($0 >= 0x20 && $0 < 0x7F) || $0 == 0 }
        if printable { return noCrypto ? .clean : .patch }
        return .decrypt
    }

    static func extractMetadata(_ url: URL) -> (titleID: String?, productCode: String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil) }
        defer { try? handle.close() }

        let fileLen = (try? handle.seekToEnd()) ?? 0
        guard fileLen > 0x1000 else { return (nil, nil) }

        let ext = url.pathExtension.lowercased()
        var partitionOffset: UInt64 = 0
        var titleID: String?

        if ext == "cia" {
            guard let _ = try? handle.seek(toOffset: 0),
                  let head = try? handle.read(upToCount: 0x20),
                  head.count == 0x20 else { return (nil, nil) }

            let certSize = readUInt32Le(from: head, offset: 8) ?? 0
            let ticketSize = readUInt32Le(from: head, offset: 12) ?? 0
            let align: (UInt64) -> UInt64 = { ($0 + 63) & ~63 }

            let certOff = align(0x20)
            let ticketOff = align(certOff + UInt64(certSize))
            let tmdOff = align(ticketOff + UInt64(ticketSize))

            guard let _ = try? handle.seek(toOffset: tmdOff + 0x18C),
                  let tIDBytes = try? handle.read(upToCount: 8),
                  tIDBytes.count == 8 else { return (nil, nil) }

            titleID = tIDBytes.map { String(format: "%02X", $0) }.joined()

            let tmdSize = readUInt32Le(from: head, offset: 16) ?? 0
            partitionOffset = align(tmdOff + UInt64(tmdSize))
        } else {
            guard let _ = try? handle.seek(toOffset: 0x120),
                  let partitionTable = try? handle.read(upToCount: 64),
                  partitionTable.count == 64 else { return (nil, nil) }
            guard let sector = readUInt32Le(from: partitionTable, offset: 0), sector > 0 else { return (nil, nil) }
            partitionOffset = UInt64(sector) * 0x200
        }

        guard let _ = try? handle.seek(toOffset: partitionOffset + 0x100),
              let ncchHead = try? handle.read(upToCount: 0x200),
              ncchHead.count == 0x200 else {
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

        var patched = false
        for partition in 0..<8 {
            guard let sector = readUInt32Le(from: partitionTable, offset: partition * 8), sector != 0 else { continue }
            let offset = UInt64(sector) * 0x200
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
}
