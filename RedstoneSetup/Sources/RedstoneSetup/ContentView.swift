import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var vm = SetupViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if vm.adbInstalled == false {
                ADBNoticeBanner(vm: vm)
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
        .navigationSubtitle(statusSummary)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.refreshDevice() }
                } label: {
                    if vm.isRefreshingDevice {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(vm.isRefreshingDevice || vm.isInstallingADB)
                .help("Check ADB and refresh tablet status")
            }
        }
        .task { await vm.refreshDevice() }
    }

    // MARK: - Status shown in the window title bar

    /// One-line summary shown as the window subtitle.
    private var statusSummary: String {
        if vm.adbInstalled == false {
            return "ADB not installed — install it to manage tablets"
        }
        switch vm.device.connection {
        case .connected:
            let parts = [
                vm.device.model,
                vm.device.androidVersion.map { "Android \($0)" },
                vm.device.resolution,
                vm.device.density,
                vm.device.battery.map { "🔋 \($0)" }
            ].compactMap { $0 }
            return parts.isEmpty ? "Tablet connected" : parts.joined(separator: "  ·  ")
        case .unauthorized:
            return "Accept the USB debugging prompt on the tablet"
        case .disconnected:
            return "Plug in a tablet to get started"
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

                Spacer(minLength: 4)

                statusBadge

                runButton
            }

            // Description — always reserve 2 lines so every card is the same height
            Text(action.step.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
