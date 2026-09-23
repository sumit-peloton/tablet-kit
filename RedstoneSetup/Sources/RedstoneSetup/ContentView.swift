import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var vm = SetupViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if vm.adbInstalled == false {
                ADBNoticeBanner(vm: vm)
            } else {
                DevicePanel(vm: vm)
            }
            ForEach(vm.categories, id: \.name) { group in
                CategorySection(vm: vm, name: group.name, actions: group.actions)
            }
            ConsoleView(vm: vm)
        }
        .padding(20)
        .frame(minWidth: 780, maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Tablet Kit")
        .task { await vm.refreshDevice() }
    }
}

// MARK: - Device Panel (one-glance status dashboard)

struct DevicePanel: View {
    @ObservedObject var vm: SetupViewModel

    private struct Stat: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private let columns = [
        GridItem(.flexible(), alignment: .topLeading),
        GridItem(.flexible(), alignment: .topLeading),
        GridItem(.flexible(), alignment: .topLeading),
        GridItem(.flexible(), alignment: .topLeading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: connection status + Refresh
            HStack(spacing: 10) {
                Image(systemName: "tablet")
                    .font(.title3)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusText)
                        .font(.headline)
                    if vm.device.connection != .connected {
                        Text(hintText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task { await vm.refreshDevice() }
                } label: {
                    HStack(spacing: 6) {
                        if vm.isRefreshingDevice {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.isRefreshingDevice)
            }
            .padding(16)

            if vm.device.connection == .connected {
                Divider()
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(stats) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.value)
                                .font(.system(.callout, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Text(stat.label.uppercased())
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var stats: [Stat] {
        var s: [Stat] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { s.append(Stat(id: label, label: label, value: value)) }
        }
        add("Generation", vm.device.generation)
        add("Platform", vm.device.platform)
        add("Android", vm.device.androidVersion.map { "Android \($0)" })
        add("Peloton OS", vm.device.pelotonOS)
        add("Resolution", vm.device.resolution)
        add("Density", vm.device.density)
        add("Serial", vm.device.serial)
        return s
    }

    private var statusColor: Color {
        switch vm.device.connection {
        case .connected:    return .green
        case .unauthorized: return .orange
        case .disconnected: return Color(NSColor.tertiaryLabelColor)
        }
    }

    private var statusText: String {
        switch vm.device.connection {
        case .connected:    return "Tablet Connected"
        case .unauthorized: return "Tablet Unauthorized"
        case .disconnected: return "No Tablet Connected"
        }
    }

    private var hintText: String {
        switch vm.device.connection {
        case .unauthorized: return "Accept the USB debugging prompt on the tablet, then Refresh."
        default:            return "Plug in a tablet and press Refresh."
        }
    }
}

// MARK: - ADB Notice Banner

/// Prominent notice shown when ADB isn't installed, with a one-tap install.
struct ADBNoticeBanner: View {
    @ObservedObject var vm: SetupViewModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Android Debug Bridge isn’t installed")
                    .font(.headline)
                Text("ADB is required to communicate with Redstone tablets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                Task { await vm.installADB() }
            } label: {
                if vm.isInstallingADB {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Installing…")
                    }
                } else {
                    Text("Install ADB")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isInstallingADB)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.30), lineWidth: 1)
        )
    }
}

// MARK: - Category Section

struct CategorySection: View {
    @ObservedObject var vm: SetupViewModel
    let name: String
    let actions: [StepState]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(0.6)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(actions) { action in
                    ActionCardView(vm: vm, action: action)
                }
            }
        }
    }
}

// MARK: - Action Card

struct ActionCardView: View {
    @ObservedObject var vm: SetupViewModel
    @ObservedObject var action: StepState
    @State private var isHovering = false

    private var isRunning: Bool {
        if case .running = action.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row
            HStack(spacing: 10) {
                iconBadge

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.step.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)

                    if action.step.isManual == true || action.step.optional == true {
                        HStack(spacing: 5) {
                            if action.step.isManual == true {
                                Badge(text: "Manual", systemImage: "hand.point.up", tint: .orange)
                            }
                            if action.step.optional == true {
                                Badge(text: "Optional", systemImage: nil, tint: .secondary)
                            }
                        }
                    }
                }

                // Picker for choice-style actions (e.g. hardware platform)
                if action.step.kind == "platformPicker", let options = action.step.options {
                    Picker("", selection: $action.selectedOptionID) {
                        ForEach(options) { option in
                            Text(option.title).tag(Optional(option.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }

                Spacer(minLength: 4)

                statusBadge

                if action.step.kind == "toggle" {
                    toggleControl
                } else {
                    runButton
                }
            }

            // Description — always reserve 2 lines so every card is the same height
            Text(action.step.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0.05),
                radius: isHovering ? 6 : 3,
                y: isHovering ? 2 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: action.step.icon ?? "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
    }

    private var toggleControl: some View {
        HStack(spacing: 6) {
            if isRunning {
                ProgressView().controlSize(.small)
            }
            Toggle("", isOn: Binding(
                get: { action.isOn },
                set: { newValue in Task { await vm.setToggle(action, on: newValue) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isRunning || vm.device.connection != .connected)
            .help("Toggle \(action.step.title)")
        }
    }

    private var runButton: some View {
        Button {
            Task { await vm.runAction(action) }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1) // optical centering of the triangle
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !isRunning ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .disabled(isRunning)
        .help("Run \(action.step.title)")
    }

    private var borderColor: Color {
        switch action.status {
        case .running:   return .blue.opacity(0.4)
        case .succeeded: return .green.opacity(0.4)
        case .failed:    return .red.opacity(0.4)
        default:         return isHovering ? .secondary.opacity(0.25) : .secondary.opacity(0.12)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch action.status {
        case .pending, .running:
            EmptyView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Small Badge

struct Badge: View {
    let text: String
    let systemImage: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.15))
        .foregroundStyle(tint)
        .clipShape(Capsule())
    }
}

// MARK: - Console (persistent command log)

struct ConsoleView: View {
    @ObservedObject var vm: SetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Console")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { vm.clearConsole() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(vm.console.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Scrollable log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if vm.console.isEmpty {
                            Text("Command output will appear here.")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(vm.console) { entry in
                                Text(entry.text.isEmpty ? " " : entry.text)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(color(for: entry.kind))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: vm.console.count) { _, _ in
                    if let last = vm.console.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 160)
            .background(Color(NSColor.textBackgroundColor))
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func color(for kind: ConsoleEntry.Kind) -> Color {
        switch kind {
        case .command: return .primary
        case .output:  return .secondary
        case .success: return .green
        case .failure: return .red
        case .info:    return .accentColor
        }
    }
}
