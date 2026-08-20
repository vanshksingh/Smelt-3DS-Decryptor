import SwiftUI

enum AppInfo {
    static let name = "Smelt"
    static let version = "1.0.2"
}

enum Analysis: String {
    case unknown = "Scanning"
    case clean = "Already Clean"
    case patch = "Needs Flag Patch"
    case decrypt = "Needs Decrypt"
    case invalid = "Invalid"
    case cia = "CIA File"
    case patched = "Flags Patched"
    case decrypted = "Decrypted"
    case processed = "Processed"

    var col: Color {
        switch self {
        case .clean, .patched, .decrypted, .processed: return Palette.green
        case .patch: return Palette.orange
        case .decrypt: return Palette.blue
        case .cia: return Palette.purple
        case .invalid: return Palette.red
        default: return .gray
        }
    }

    var icon: String {
        switch self {
        case .clean, .patched, .decrypted, .processed: return "checkmark.shield.fill"
        case .patch: return "wrench.and.screwdriver.fill"
        case .decrypt: return "lock.fill"
        case .cia: return "doc.badge.arrow.up.fill"
        case .invalid: return "exclamationmark.triangle.fill"
        default: return "ellipsis.circle"
        }
    }
}

enum RState: Equatable {
    case queued, scanning, running, done, failed, skipped

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .scanning: return "Scanning"
        case .running: return "Processing"
        case .done: return "Done"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }

    var col: Color {
        switch self {
        case .queued: return Palette.orange
        case .scanning: return Palette.blue.opacity(0.7)
        case .running: return Palette.blue
        case .done: return Palette.green
        case .failed: return Palette.red
        case .skipped: return .gray
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case same = "Same as Input (CCI Fallback)"
    case to3DS = "Convert to 3DS"
    case toCCI = "Convert to CCI"

    var id: String { rawValue }
}

struct ROM: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let ext: String
    let size: String
    var state: RState = .queued
    var analysis: Analysis = .unknown
    var progress: Double = 0
    var note: String = ""
    var outputURL: URL?
    var logs: [String] = []
    var titleID: String?
    var productCode: String?

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
}
