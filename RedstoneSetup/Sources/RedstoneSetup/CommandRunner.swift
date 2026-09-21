import Foundation

/// Runs a single shell command and streams stdout+stderr line-by-line via a callback.
/// Returns the exit code when complete.
actor CommandRunner {

    /// Run `shell` string via `/bin/bash -c` and stream output.
    /// - Parameters:
    ///   - shell: The shell command string
    ///   - onOutput: Called on the main actor with each output line
    /// - Returns: Exit code (0 = success)
    func run(
        shell: String,
        onOutput: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", shell]

        // When launched as a .app bundle (via `open`), the process inherits a
        // minimal PATH that omits Homebrew, so `adb`/`brew` aren't found. Prepend
        // the common Homebrew locations so tools resolve the same as in a terminal.
        var env = ProcessInfo.processInfo.environment
        let homebrewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(homebrewPaths):\(existingPath)"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Stream stdout
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    onOutput(text)
                }
            }
        }

        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    onOutput("[stderr] \(text)")
                }
            }
        }

        process.launch()
        process.waitUntilExit()

        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil

        // Drain any remaining bytes
        let remainingOut = outHandle.readDataToEndOfFile()
        let remainingErr = errHandle.readDataToEndOfFile()
        if !remainingOut.isEmpty, let text = String(data: remainingOut, encoding: .utf8) {
            await MainActor.run { onOutput(text) }
        }
        if !remainingErr.isEmpty, let text = String(data: remainingErr, encoding: .utf8) {
            await MainActor.run { onOutput("[stderr] \(text)") }
        }

        return process.terminationStatus
    }
}
