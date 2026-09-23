import Foundation

// MARK: - Data Models (loaded from setup_flows.json)

struct SetupFlowCatalog: Codable {
    let flows: [SetupFlow]
}

struct SetupFlow: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let steps: [SetupStep]
}

struct SetupStep: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let requiresDevice: Bool
    let isManual: Bool?
    let optional: Bool?
    let commands: [StepCommand]
    /// Dashboard grouping, e.g. "Connection", "Display". Defaults to "General".
    var category: String? = nil
    /// Optional SF Symbol shown on the action card.
    var icon: String? = nil
    /// Special behavior, e.g. "installApks" opens a file picker instead of
    /// running the listed commands verbatim. `nil` = run commands normally.
    var kind: String? = nil
    /// If true, a confirmation dialog is shown before the action runs.
    var confirm: Bool? = nil
    /// Optional custom text for that confirmation dialog.
    var confirmMessage: String? = nil
    /// Options for a picker-style action. When present with
    /// `kind == "platformPicker"`, the card shows a dropdown and runs the
    /// selected option's shell instead of the listed commands.
    var options: [StepOption]? = nil
    /// For `kind == "toggle"`: commands run to turn the toggle OFF. The
    /// existing `commands` array is used to turn it ON.
    var offCommands: [StepCommand]? = nil
    /// For `kind == "toggle"`: shell command whose output reflects the current
    /// on/off state, checked against `onPattern` during a device refresh.
    var stateCommand: String? = nil
    /// For `kind == "toggle"`: if `stateCommand`'s output matches, the toggle
    /// is considered ON. Defaults to `"true"` when omitted.
    var onPattern: String? = nil
}

struct StepCommand: Codable, Identifiable {
    let id: String
    let label: String
    let shell: String
    let successPattern: String?
    let failureMessage: String?
}

/// A single selectable choice for a picker-style action.
struct StepOption: Codable, Identifiable {
    let id: String
    let title: String
    let shell: String
    let successPattern: String?
}

// MARK: - Device Status

/// Snapshot of the connected tablet, shown in the dashboard status bar.
struct DeviceInfo: Equatable {
    enum Connection: Equatable {
        case disconnected
        case unauthorized
        case connected
    }

    var connection: Connection = .disconnected
    /// Physical tablet hardware generation (e.g. Redstone, Topaz).
    var generation: String?
    var androidVersion: String?
    /// Peloton OS version (ro.peloton.os.version).
    var pelotonOS: String?
    var serial: String?
    /// Currently emulated Peloton platform (Bike / Row / Tread / Tread+).
    var platform: String?
    var resolution: String?
    var density: String?

    static let disconnected = DeviceInfo()
}

// MARK: - Console Log

/// A single line in the persistent console at the bottom of the dashboard.
struct ConsoleEntry: Identifiable {
    enum Kind {
        case command   // the shell command being sent
        case output    // stdout/stderr from the command
        case success   // a command finished successfully
        case failure   // a command failed
        case info      // section separators / action headers
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

// MARK: - Runtime State

enum StepStatus: Equatable {
    case pending
    case running
    case succeeded
    case failed(String)
    case skipped

    var icon: String {
        switch self {
        case .pending:  return "circle"
        case .running:  return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        case .skipped:  return "minus.circle"
        }
    }

    var color: String {
        switch self {
        case .pending:  return "gray"
        case .running:  return "blue"
        case .succeeded: return "green"
        case .failed:   return "red"
        case .skipped:  return "orange"
        }
    }

    var label: String {
        switch self {
        case .pending:        return "Pending"
        case .running:        return "Running..."
        case .succeeded:      return "Complete"
        case .failed(let m):  return "Failed: \(m)"
        case .skipped:        return "Skipped"
        }
    }
}

enum CommandStatus: Equatable {
    case pending
    case running
    case succeeded
    case failed(String)
}

@MainActor
class CommandState: ObservableObject, Identifiable {
    let id: String
    let command: StepCommand
    @Published var status: CommandStatus = .pending
    @Published var output: String = ""

    init(command: StepCommand) {
        self.id = command.id
        self.command = command
    }
}

@MainActor
class StepState: ObservableObject, Identifiable {
    let id: String
    let step: SetupStep
    @Published var status: StepStatus = .pending
    @Published var commandStates: [CommandState]
    @Published var isExpanded: Bool = false
    /// Currently selected option id for picker-style actions.
    @Published var selectedOptionID: String?
    /// Current on/off state for `kind == "toggle"` actions. Refreshed from the
    /// device on each `refreshDevice()`.
    @Published var isOn: Bool = false

    init(step: SetupStep) {
        self.id = step.id
        self.step = step
        self.commandStates = step.commands.map { CommandState(command: $0) }
        self.selectedOptionID = step.options?.first?.id
    }
}
