// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RedstoneSetup",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "RedstoneSetup",
            path: "Sources/RedstoneSetup",
            resources: [
                .copy("Resources/setup_flows.json")
            ]
        )
    ]
)
