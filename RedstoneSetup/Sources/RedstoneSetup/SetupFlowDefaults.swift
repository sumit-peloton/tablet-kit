import Foundation

/// Embedded fallback flows — used if setup_flows.json can't be found at runtime.
/// These mirror setup_flows.json so the app always has something to show.
/// Edit setup_flows.json to add/modify flows; this file is a safety net.
enum SetupFlowDefaults {
    static let flows: [SetupFlow] = [
        SetupFlow(
            id: "redstone-tablet-setup",
            name: "Redstone Tablet Setup",
            description: "Full setup flow for Peloton Redstone design review tablets",
            icon: "tabletsymbol",
            steps: [
                SetupStep(
                    id: "check-adb",
                    title: "Check ADB Installation",
                    description: "Verify that Android Debug Bridge (ADB) is installed on your Mac.",
                    requiresDevice: false,
                    isManual: nil,
                    optional: nil,
                    commands: [
                        StepCommand(
                            id: "adb-version",
                            label: "Check ADB version",
                            shell: "adb version",
                            successPattern: "Android Debug Bridge",
                            failureMessage: "ADB not found. Install via: brew install android-platform-tools"
                        )
                    ]
                ),
                SetupStep(
                    id: "install-adb",
                    title: "Install ADB (if needed)",
                    description: "Install Android Debug Bridge via Homebrew. Skip if already installed.",
                    requiresDevice: false,
                    isManual: nil,
                    optional: true,
                    commands: [
                        StepCommand(
                            id: "brew-install-adb",
                            label: "Install android-platform-tools",
                            shell: "brew install android-platform-tools",
                            successPattern: "already installed|Successfully installed",
                            failureMessage: "Homebrew installation failed."
                        )
                    ]
                ),
                SetupStep(
                    id: "connect-device",
                    title: "Connect Tablet via USB",
                    description: "Plug the Redstone tablet into your Mac with a USB-C cable. Ensure Developer Options and USB Debugging are enabled.",
                    requiresDevice: false,
                    isManual: true,
                    optional: nil,
                    commands: [
                        StepCommand(
                            id: "wait-device",
                            label: "Detect connected device",
                            shell: "adb devices | grep -v 'List of' | grep -v '^$' | head -5",
                            successPattern: "device",
                            failureMessage: "No device detected. Check USB Debugging is enabled."
                        )
                    ]
                ),
                SetupStep(
                    id: "device-info",
                    title: "Verify Device Info",
                    description: "Confirm we're connected to the correct Redstone tablet.",
                    requiresDevice: true,
                    isManual: nil,
                    optional: nil,
                    commands: [
                        StepCommand(id: "get-model", label: "Get device model", shell: "adb shell getprop ro.product.model", successPattern: nil, failureMessage: nil),
                        StepCommand(id: "get-android-version", label: "Get Android version", shell: "adb shell getprop ro.build.version.release", successPattern: nil, failureMessage: nil),
                        StepCommand(id: "get-serial", label: "Get device serial", shell: "adb get-serialno", successPattern: nil, failureMessage: nil)
                    ]
                ),
                SetupStep(
                    id: "configure-display",
                    title: "Configure Display Settings",
                    description: "Set display density and font scale optimized for design review.",
                    requiresDevice: true,
                    isManual: nil,
                    optional: nil,
                    commands: [
                        StepCommand(id: "set-density", label: "Set display density", shell: "adb shell wm density 420", successPattern: nil, failureMessage: nil),
                        StepCommand(id: "set-font-scale", label: "Set font scale to 1.0", shell: "adb shell settings put system font_scale 1.0", successPattern: nil, failureMessage: nil),
                        StepCommand(id: "disable-animations", label: "Reduce animations", shell: "adb shell settings put global window_animation_scale 0.5", successPattern: nil, failureMessage: nil)
                    ]
                ),
                SetupStep(
                    id: "verify-setup",
                    title: "Verify Setup Complete",
                    description: "Run a final check to confirm the device is ready for design review.",
                    requiresDevice: true,
                    isManual: nil,
                    optional: nil,
                    commands: [
                        StepCommand(id: "final-check", label: "Final device status", shell: "adb devices | grep 'device$'", successPattern: nil, failureMessage: nil),
                        StepCommand(id: "get-display-info", label: "Confirm display settings", shell: "adb shell wm size && adb shell wm density", successPattern: nil, failureMessage: nil)
                    ]
                )
            ]
        )
    ]
}
