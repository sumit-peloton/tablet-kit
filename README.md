# Redstone Setup App

A native macOS SwiftUI app for Peloton product designers to manage Redstone design-review tablets. A dashboard shows the connected tablet's status and a grid of run-on-demand actions (grouped by category) with real-time command output.

---

## Quick Start

### Option A — Swift Package (command-line, fastest)

```bash
cd /tmp/redstone-setup-app/RedstoneSetup
./build-and-run.sh
```

### Option B — Open in Xcode (recommended for daily use)

```bash
cd /tmp/redstone-setup-app/RedstoneSetup
open Package.swift          # Xcode opens and resolves the package automatically
```

In Xcode:
1. Select the `RedstoneSetup` scheme
2. Choose **My Mac** as destination
3. Press **⌘R** to build and run

---

## Project Structure

```
RedstoneSetup/
├── Package.swift                          # Swift Package manifest
├── build-and-run.sh                       # One-command build + run
├── create-xcode-project.sh               # Generate .xcodeproj
└── Sources/RedstoneSetup/
    ├── RedstoneSetupApp.swift             # @main entry point
    ├── ContentView.swift                  # UI: status bar + action-card grid
    ├── Models.swift                       # Data types (SetupFlow, StepCommand, DeviceInfo, etc.)
    ├── SetupViewModel.swift               # Loads actions, runs them on demand, refreshes device status
    ├── CommandRunner.swift                # Process executor with live output streaming
    ├── SetupFlowDefaults.swift            # Embedded fallback flows (Swift constants)
    └── Resources/
        └── setup_flows.json              # ← EDIT THIS to add/modify commands
```

---

## How to Add or Modify Actions

All actions live in **`Sources/RedstoneSetup/Resources/setup_flows.json`**. No Swift code changes needed for new actions. The dashboard flattens every step across all flows into one grid, grouped by `category`.

### Adding a new action

```json
{
  "id": "my-new-action",
  "title": "My New Action",
  "description": "What this action does and any manual instructions.",
  "category": "Utilities",
  "icon": "wrench.and.screwdriver",
  "requiresDevice": true,
  "optional": false,
  "commands": [
    {
      "id": "cmd-1",
      "label": "Human-readable label",
      "shell": "adb shell some-command",
      "successPattern": "expected output substring",
      "failureMessage": "What to show if this fails"
    }
  ]
}
```

Add it to the `steps` array of the flow. Give it a `category` to control which dashboard section its card appears under (a new category name creates a new section automatically). The app picks up changes on next launch.

### Action fields

| Field | Required | Description |
|---|---|---|
| `id` | ✅ | Unique identifier |
| `title` | ✅ | Shown on the action card |
| `description` | ✅ | Shown on the card (supports newlines) |
| `requiresDevice` | ✅ | Informational (future: auto-check ADB) |
| `category` | ❌ | Dashboard section the card is grouped under (e.g. `Display`, `Setup`, `Tools`). Defaults to `General` |
| `icon` | ❌ | SF Symbol name shown on the card |
| `kind` | ❌ | Special behavior. `installApks` opens a native file picker and runs the first command (e.g. `adb install -r`) against each chosen `.apk`. Omit for normal commands |
| `confirm` | ❌ | If `true`, a confirmation dialog is shown before the action runs |
| `confirmMessage` | ❌ | Custom text for that confirmation dialog (falls back to `description`) |
| `isManual` | ❌ | Shows a "Manual" badge — reminds user to act on tablet |
| `optional` | ❌ | If `true`, a failed run is marked "Skipped" rather than "Failed" |
| `commands` | ✅ | Array of shell commands run in order when the card's Run button is pressed |

### Command fields

| Field | Required | Description |
|---|---|---|
| `id` | ✅ | Unique within the step |
| `label` | ✅ | Short human label |
| `shell` | ✅ | Shell command (run via `/bin/bash -c`) |
| `successPattern` | ❌ | Substring that must appear in output; if absent, exit code 0 is used |
| `failureMessage` | ❌ | Message shown on failure |

---

## Architecture

```
SetupViewModel (ObservableObject)
  ├── loads actions from setup_flows.json → [StepState]
  │     └── each holds [CommandState] (one per command)
  ├── categories — actions grouped by `category` for the dashboard
  ├── runAction(_:) — runs one action's commands on demand
  │     └── runCommand() via CommandRunner
  ├── refreshDevice() — checks ADB, then `adb devices` + getprops + wm size/density → DeviceInfo
  ├── installADB() — `brew install android-platform-tools`, then re-checks
  └── publishes actions / device / adbInstalled / isRefreshingDevice

CommandRunner (actor)
  └── run(shell:onOutput:) → /bin/bash -c
        ├── streams stdout/stderr line-by-line via readabilityHandler
        └── returns exit code when process exits

ContentView (dashboard)
  ├── DeviceStatusBar — ADB check + Install prompt, or connection dot,
  │                     model · Android · resolution · density · serial · battery, Refresh
  └── ScrollView of CategorySection (one per category)
        └── LazyVGrid of ActionCardView (Run button, status, expandable output)
              └── CommandRowView (per-command output terminal)
```

---

## Requirements

- macOS 26 or later
- Xcode 26+ (for building)
- ADB installed: `brew install android-platform-tools`
- Redstone tablet with Developer Options + USB Debugging enabled

---

## Note on Source Materials

This app was scaffolded based on the Redstone tablet setup workflow. The commands in `setup_flows.json` cover common ADB-based tablet provisioning. **Update the JSON with your exact commands** from your setup doc once you open the project in Xcode.
