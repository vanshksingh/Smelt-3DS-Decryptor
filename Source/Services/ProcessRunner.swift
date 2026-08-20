import Foundation

enum ProcessRunner {
    @discardableResult
    static func run(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL,
        environment: [String: String]? = nil,
        log: ((String) -> Void)? = nil,
        logPrefix: String? = nil
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        if let log {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                forward(handle.availableData, prefix: logPrefix, log: log)
            }
        }

        do {
            try process.run()
        } catch {
            throw smeltError("Failed to launch \(executable.lastPathComponent): \(error.localizedDescription)")
        }

        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        if let remaining = try? pipe.fileHandleForReading.readToEnd(), let log {
            forward(remaining, prefix: logPrefix, log: log)
        }

        if process.terminationStatus == 9 {
            throw smeltError("macOS blocked \(executable.lastPathComponent) (Gatekeeper). Allow Smelt in System Settings → Privacy & Security, then try again.")
        }

        return process.terminationStatus
    }

    static func forward(_ data: Data, prefix: String?, log: (String) -> Void) {
        guard !data.isEmpty, let string = String(data: data, encoding: .utf8), !string.isEmpty else { return }
        let cleaned = string.replacingOccurrences(of: "\r", with: "\n")
        for line in cleaned.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let prefix {
                    log("[\(prefix)] \(trimmed)")
                } else {
                    log(trimmed)
                }
            }
        }
    }
}
