import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class SetupViewModel: ObservableObject {
    /// All actions available on the dashboard (flattened from the loaded catalog).
    @Published var actions: [StepState] = []
    /// Current tablet status shown in the top status bar.
    @Published var device: DeviceInfo = .disconnected
    @Published var isRefreshingDevice: Bool = false
    /// Whether ADB is installed on the Mac. `nil` until the first check completes.
    @Published var adbInstalled: Bool?
    @Published var isInstallingADB: Bool = false
    @Published var errorMessage: String?
    /// Rolling log of commands + output shown in the persistent console.
    @Published var console: [ConsoleEntry] = []

    private let runner = CommandRunner()

    // MARK: - Console logging

    private func log(_ text: String, _ kind: ConsoleEntry.Kind = .output) {
        console.append(ConsoleEntry(kind: kind, text: text))
    }

    func clearConsole() {
        console.removeAll()
    }

    init() {
        loadActions()
    }

    /// Actions grouped by category, preserving the order they appear in the catalog.
    var categories: [(name: String, actions: [StepState])] {
        var order: [String] = []
        var buckets: [String: [StepState]] = [:]
        for action in actions {
            let category = action.step.category ?? "General"
            if buckets[category] == nil {
                buckets[category] = []
                order.append(category)
            }
            buckets[category]?.append(action)
        }
        return order.map { (name: $0, actions: buckets[$0] ?? []) }
    }

    // MARK: - Load actions from bundled JSON

    func loadActions() {
        if let url = Bundle.module.url(forResource: "setup_flows", withExtension: "json") {
            decode(from: url); return
        }
        if let url = Bundle.main.url(forResource: "setup_flows", withExtension: "json") {
            decode(from: url); return
        }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let sidecar = execDir.appendingPathComponent("setup_flows.json")
        if FileManager.default.fileExists(atPath: sidecar.path) {
            decode(from: sidecar); return
        }
        // Last resort: embedded defaults
        buildActions(from: SetupFlowDefaults.flows)
    }

    private func decode(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(SetupFlowCatalog.self, from: data)
            buildActions(from: catalog.flows)
        } catch {
            errorMessage = "Failed to load setup actions: \(error.localizedDescription)"
            buildActions(from: SetupFlowDefaults.flows)
        }
    }

    private func buildActions(from flows: [SetupFlow]) {
        // The dashboard shows a single flat catalog of actions across all flows.
        let steps = flows.flatMap { $0.steps }
        actions = steps.map { StepState(step: $0) }
    }

    // MARK: - Run a single action on demand

    func runAction(_ action: StepState) async {
        if case .running = action.status { return }

        // Special flows (e.g. APK installer with a file picker).
        if action.step.kind == "installApks" {
            await runInstallApks(action)
            return
        }

        // Picker-style action: run the selected option's shell.
        if action.step.kind == "platformPicker" {
            await runSelectedOption(action)
            return
        }

        // Push an image and open it on the tablet's screen.
        if action.step.kind == "displayImage" {
            await runDisplayImage(action)
            return
        }

        // Optional confirmation dialog before running.
        if action.step.confirm == true, !confirmRun(action) {
            return
        }

        action.status = .running
        log("▸ \(action.step.title)", .info)

        var allSucceeded = true
        for cmdState in action.commandStates {
            let ok = await runCommand(cmdState)
            if !ok { allSucceeded = false }
        }

        if allSucceeded {
            action.status = .succeeded
        } else if action.step.optional ?? false {
            action.status = .skipped
        } else {
            action.status = .failed("One or more commands failed")
        }
    }

    // MARK: - Toggle-style action (e.g. debug overlays)

    /// Turn a `kind == "toggle"` action on or off, running the matching command
    /// set. Optimistically reverts the switch if the tablet isn't connected.
    func setToggle(_ action: StepState, on: Bool) async {
        if case .running = action.status { return }

        guard device.connection == .connected else {
            log("▸ \(action.step.title)", .info)
            log("✕ No tablet connected — plug in a tablet and press Refresh", .failure)
            action.isOn = !on // revert the switch
            action.status = .failed("No tablet connected")
            return
        }

        let commands = on ? action.step.commands : (action.step.offCommands ?? [])
        guard !commands.isEmpty else { return }

        action.status = .running
        log("▸ \(action.step.title): \(on ? "On" : "Off")", .info)

        var allSucceeded = true
        for command in commands {
            let ok = await runCommand(CommandState(command: command))
            if !ok { allSucceeded = false }
        }

        if allSucceeded {
            action.status = .succeeded
            action.isOn = on
        } else {
            action.status = .failed("One or more commands failed")
            action.isOn = !on // revert the switch to reflect the failure
        }
    }

    // MARK: - Picker-style action (e.g. hardware platform)

    private func runSelectedOption(_ action: StepState) async {
        guard let options = action.step.options, !options.isEmpty else { return }
        let selectedID = action.selectedOptionID ?? options.first?.id
        guard let option = options.first(where: { $0.id == selectedID }) ?? options.first else { return }

        guard device.connection == .connected else {
            log("▸ \(action.step.title)", .info)
            log("✕ No tablet connected — plug in a tablet and press Refresh", .failure)
            action.status = .failed("No tablet connected")
            return
        }

        action.status = .running
        log("▸ \(action.step.title): \(option.title)", .info)

        let command = StepCommand(
            id: option.id,
            label: "Set hardware to \(option.title)",
            shell: option.shell,
            successPattern: option.successPattern,
            failureMessage: nil
        )
        let ok = await runCommand(CommandState(command: command))
        action.status = ok ? .succeeded : .failed("Command failed")
    }

    // MARK: - APK installer (file picker)

    private func runInstallApks(_ action: StepState) async {
        guard device.connection == .connected else {
            log("▸ \(action.step.title)", .info)
            log("✕ No tablet connected — plug in a tablet and press Refresh", .failure)
            action.status = .failed("No tablet connected")
            return
        }
        guard let urls = pickAPKs(), !urls.isEmpty else { return }

        action.status = .running
        log("▸ \(action.step.title)", .info)
        let cmdState = action.commandStates.first
        cmdState?.status = .running
        cmdState?.output = ""

        let base = action.step.commands.first?.shell ?? "adb install -r"
        var allSucceeded = true

        for url in urls {
            let shell = "\(base) \"\(url.path)\""
            cmdState?.output += "$ \(shell)\n"
            log("$ \(shell)", .command)
            let (code, out) = await capture(shell)
            cmdState?.output += out
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { log(trimmed, .output) }
            // adb prints "Success" on a successful install.
            if code != 0 || (!out.isEmpty && !out.contains("Success")) {
                allSucceeded = false
                log("✕ \(url.lastPathComponent) failed to install", .failure)
            } else {
                log("✓ Installed \(url.lastPathComponent)", .success)
            }
            cmdState?.output += "\n"
        }

        cmdState?.status = allSucceeded ? .succeeded : .failed("Install failed")
        action.status = allSucceeded ? .succeeded : .failed("One or more APKs failed to install")
    }

    // MARK: - Display an image on the tablet

    private func runDisplayImage(_ action: StepState) async {
        guard device.connection == .connected else {
            log("▸ \(action.step.title)", .info)
            log("✕ No tablet connected — plug in a tablet and press Refresh", .failure)
            action.status = .failed("No tablet connected")
            return
        }
        guard let url = pickImage() else { return }

        action.status = .running
        log("▸ \(action.step.title): \(url.lastPathComponent)", .info)

        // Push to a fixed, space-free path so the file:// URI stays simple.
        let ext = url.pathExtension.lowercased()
        let remote = "/sdcard/Download/tabletkit-display.\(ext.isEmpty ? "png" : ext)"
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "png":         mime = "image/png"
        case "gif":         mime = "image/gif"
        case "webp":        mime = "image/webp"
        default:            mime = "image/*"
        }

        // 1. Push the image onto the tablet.
        let push = "adb push \"\(url.path)\" \"\(remote)\""
        log("$ \(push)", .command)
        let (pushCode, pushOut) = await capture(push)
        let pushTrimmed = pushOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pushTrimmed.isEmpty { log(pushTrimmed, .output) }
        guard pushCode == 0 else {
            log("✕ Failed to push image to tablet", .failure)
            action.status = .failed("Push failed")
            return
        }

        // 2. Nudge the media scanner so viewers notice the new file (best effort).
        let scan = "adb shell \"am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://\(remote)\""
        log("$ \(scan)", .command)
        let (_, scanOut) = await capture(scan)
        let scanTrimmed = scanOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scanTrimmed.isEmpty { log(scanTrimmed, .output) }

        // 3. Open it with a VIEW intent.
        let view = "adb shell am start -a android.intent.action.VIEW -d file://\(remote) -t \(mime)"
        log("$ \(view)", .command)
        let (viewCode, viewOut) = await capture(view)
        let viewTrimmed = viewOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !viewTrimmed.isEmpty { log(viewTrimmed, .output) }

        let lower = viewOut.lowercased()
        if viewCode != 0 || lower.contains("no activity found") || lower.contains("error:") {
            log("✕ Couldn't open the image — the tablet may have no image viewer, or its home app is locked", .failure)
            action.status = .failed("No image viewer on tablet")
        } else {
            log("✓ Displaying \(url.lastPathComponent) on the tablet", .success)
            action.status = .succeeded
        }
    }

    /// Show a native file picker for a single image file.
    private func pickImage() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an Image to Display"
        panel.prompt = "Display"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls.first : nil
    }

    /// Show a native file picker for `.apk` files.
    private func pickAPKs() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Choose APKs to Install"
        panel.prompt = "Install"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let apkType = UTType(filenameExtension: "apk") {
            panel.allowedContentTypes = [apkType]
        }
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/redstone-apks")
        if FileManager.default.fileExists(atPath: defaultDir.path) {
            panel.directoryURL = defaultDir
        }
        return panel.runModal() == .OK ? panel.urls : nil
    }

    // MARK: - Confirmation dialog

    private func confirmRun(_ action: StepState) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Run \u{201C}\(action.step.title)\u{201D}?"
        alert.informativeText = action.step.confirmMessage ?? action.step.description
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func runCommand(_ cmdState: CommandState) async -> Bool {
        cmdState.status = .running
        cmdState.output = ""

        let shell = cmdState.command.shell
        let successPattern = cmdState.command.successPattern
        let failureMessage = cmdState.command.failureMessage

        var collectedOutput = ""
        var lineBuffer = ""

        log("$ \(shell)", .command)

        do {
            let exitCode = try await runner.run(shell: shell) { chunk in
                cmdState.output += chunk
                collectedOutput += chunk
                // Emit complete lines to the console as they stream in.
                lineBuffer += chunk
                while let nl = lineBuffer.firstIndex(of: "\n") {
                    self.log(String(lineBuffer[..<nl]), .output)
                    lineBuffer = String(lineBuffer[lineBuffer.index(after: nl)...])
                }
            }
            if !lineBuffer.isEmpty { log(lineBuffer, .output) }

            let succeeded: Bool
            if let pattern = successPattern {
                succeeded = matches(collectedOutput, anyOf: pattern) || exitCode == 0
            } else {
                succeeded = exitCode == 0
            }

            if succeeded {
                cmdState.status = .succeeded
                log("✓ \(cmdState.command.label)", .success)
            } else {
                let msg = failureMessage ?? "Exit code \(exitCode)"
                cmdState.status = .failed(msg)
                if cmdState.output.isEmpty { cmdState.output = msg }
                log("✕ \(msg)", .failure)
            }
            return succeeded
        } catch {
            let msg = failureMessage ?? error.localizedDescription
            cmdState.status = .failed(msg)
            cmdState.output += "\nError: \(error.localizedDescription)"
            log("✕ \(msg)", .failure)
            return false
        }
    }

    /// `successPattern` may contain `|`-separated alternatives.
    private func matches(_ output: String, anyOf pattern: String) -> Bool {
        pattern.split(separator: "|").contains { output.contains($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - ADB installation

    /// Install Android Debug Bridge via Homebrew, then re-check status.
    func installADB() async {
        guard !isInstallingADB else { return }
        isInstallingADB = true
        errorMessage = nil
        let (code, out) = await capture("brew install android-platform-tools")
        isInstallingADB = false
        if code != 0 && !out.contains("already installed") {
            errorMessage = "Couldn't install ADB via Homebrew. Is Homebrew installed? See https://brew.sh"
        }
        await refreshDevice()
    }

    // MARK: - Device status (manual refresh)

    func refreshDevice() async {
        guard !isRefreshingDevice else { return }
        isRefreshingDevice = true
        defer { isRefreshingDevice = false }

        // Automatically check whether ADB is available before anything else.
        let (adbCode, _) = await capture("command -v adb")
        guard adbCode == 0 else {
            adbInstalled = false
            device = .disconnected
            return
        }
        adbInstalled = true

        let (_, devicesOut) = await capture("adb devices")
        let deviceLines = devicesOut
            .components(separatedBy: "\n")
            .filter { $0.contains("\t") }

        var info = DeviceInfo()
        if deviceLines.contains(where: { $0.hasSuffix("device") }) {
            info.connection = .connected
        } else if deviceLines.contains(where: { $0.hasSuffix("unauthorized") }) {
            info.connection = .unauthorized
        } else {
            info.connection = .disconnected
        }

        if info.connection == .connected {
            if let board = await captureTrimmed("adb shell getprop ro.boot.carrier_board"),
               !board.isEmpty {
                info.generation = board.capitalized
            }
            info.androidVersion = await captureTrimmed("adb shell getprop ro.build.version.release")
            info.pelotonOS = await captureTrimmed("adb shell getprop ro.peloton.os.version")
            info.serial = await captureTrimmed("adb get-serialno")
            if let raw = await captureTrimmed("adb shell settings get global peloton_platform"),
               raw != "null" {
                info.platform = friendlyPlatform(raw)
            }
            // Confirm display settings (formerly the "Verify Setup" action).
            if let size = await captureTrimmed("adb shell wm size") {
                info.resolution = size
                    .components(separatedBy: "\n").first?
                    .components(separatedBy: ": ").last?
                    .trimmingCharacters(in: .whitespaces)
            }
            if let dens = await captureTrimmed("adb shell wm density") {
                if let value = dens
                    .components(separatedBy: "\n").first?
                    .components(separatedBy: ": ").last?
                    .trimmingCharacters(in: .whitespaces) {
                    info.density = "\(value)dpi"
                }
            }

            // Reflect the current on/off state of any toggle actions.
            for action in actions where action.step.kind == "toggle" {
                guard let stateCommand = action.step.stateCommand else { continue }
                let output = (await captureTrimmed(stateCommand)) ?? ""
                action.isOn = matches(output, anyOf: action.step.onPattern ?? "true")
            }
        }

        device = info
    }

    /// Map the raw `peloton_platform` value to the design-review name.
    private func friendlyPlatform(_ raw: String) -> String {
        switch raw.lowercased() {
        case "titan":  return "Bike"
        case "caesar": return "Row"
        case "prism":  return "Tread"
        case "aurora": return "Tread+"
        default:       return raw
        }
    }

    /// Run a shell command and return its exit code plus combined output.
    private func capture(_ shell: String) async -> (Int32, String) {
        var out = ""
        let code = (try? await runner.run(shell: shell) { out += $0 }) ?? -1
        return (code, out)
    }

    private func captureTrimmed(_ shell: String) async -> String? {
        let (_, out) = await capture(shell)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
