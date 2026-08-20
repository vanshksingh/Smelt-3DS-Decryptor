import Foundation

enum ToolchainService {
    static let binaryNames = ["cia-unix", "ctrdecrypt", "ctrtool", "makerom"]
    static let resourceNames = binaryNames + ["seeddb.bin"]

    static func prepare() {
        let bundlePath = Bundle.main.bundlePath
        stripQuarantine(at: bundlePath)

        guard let resources = Bundle.main.resourceURL else { return }
        chmodExecutable(at: resources.path)

        for name in binaryNames {
            let url = resources.appendingPathComponent(name)
            chmodExecutable(at: url.path)
            stripQuarantine(at: url.path)
        }
    }

    static func verify() throws {
        for name in binaryNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
                throw smeltError("Missing dependency: \(name)")
            }
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw smeltError("Helper binary is not executable: \(name)")
            }
            _ = url
        }
        if Bundle.main.url(forResource: "seeddb.bin", withExtension: nil) == nil {
            throw smeltError("Missing dependency: seeddb.bin")
        }
    }

    static func url(named name: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            throw smeltError("Missing dependency: \(name)")
        }
        return url
    }

    /// Copy helpers into an isolated workspace and make sure they are executable.
    static func stage(into directory: URL) throws {
        let fm = FileManager.default
        for name in resourceNames {
            let src = try url(named: name)
            let dest = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: src, to: dest)
            stripQuarantine(at: dest.path)
            if binaryNames.contains(name) {
                chmodExecutable(at: dest.path)
            }
        }
    }

    static func chmodExecutable(at path: String) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        run("/bin/chmod", ["+x", path])
    }

    static func stripQuarantine(at path: String) {
        run("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", path])
    }

    private static func run(_ launchPath: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

func smeltError(_ message: String, code: Int = 1) -> NSError {
    NSError(domain: "Smelt", code: code, userInfo: [NSLocalizedDescriptionKey: message])
}
