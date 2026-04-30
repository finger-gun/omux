// swift-tools-version: 6.0
import Foundation
import PackageDescription

let ghosttyXCFrameworkPath = "Vendor/ghostty/macos/GhosttyKit.xcframework"
let hasGhosttyXCFramework = FileManager.default.fileExists(atPath: ghosttyXCFrameworkPath)

var terminalBridgeDependencies: [Target.Dependency] = ["OmuxCore"]
var terminalBridgeLinkerSettings: [LinkerSetting] = []
if hasGhosttyXCFramework {
    terminalBridgeDependencies.append("CGhostty")
    terminalBridgeDependencies.append("GhosttyKit")
    terminalBridgeLinkerSettings.append(.linkedLibrary("c++"))
    terminalBridgeLinkerSettings.append(.linkedFramework("Carbon"))
}

var targets: [Target] = [
    .target(name: "OmuxCore"),
]

if hasGhosttyXCFramework {
    targets.append(
        .binaryTarget(
            name: "GhosttyKit",
            path: ghosttyXCFrameworkPath
        )
    )
    targets.append(
        .target(
            name: "CGhostty",
            dependencies: ["GhosttyKit"],
            path: "Sources/CGhostty"
        )
    )
}

targets.append(
    .target(
        name: "OmuxTerminalBridge",
        dependencies: terminalBridgeDependencies,
        linkerSettings: terminalBridgeLinkerSettings
    )
)
targets.append(
    contentsOf: [
        .target(
            name: "OmuxControlPlane",
            dependencies: ["OmuxCore"]
        ),
        .target(
            name: "OmuxHooks",
            dependencies: ["OmuxCore"]
        ),
        .target(
            name: "OmuxCLI",
            dependencies: ["OmuxControlPlane", "OmuxCore"],
            path: "Sources/OmuxCLI"
        ),
        .target(
            name: "OmuxAppShell",
            dependencies: [
                "OmuxCore",
                "OmuxTerminalBridge",
                "OmuxControlPlane",
                "OmuxHooks",
            ]
        ),
        .executableTarget(
            name: "OpenMUXApp",
            dependencies: ["OmuxAppShell"]
        ),
        .executableTarget(
            name: "omux",
            dependencies: ["OmuxCLI"]
        ),
        .testTarget(
            name: "OmuxCoreTests",
            dependencies: ["OmuxCore"]
        ),
        .testTarget(
            name: "OmuxTerminalBridgeTests",
            dependencies: ["OmuxTerminalBridge", "OmuxCore"]
        ),
        .testTarget(
            name: "OmuxControlPlaneTests",
            dependencies: ["OmuxControlPlane", "OmuxCore"]
        ),
        .testTarget(
            name: "OmuxCLITests",
            dependencies: ["OmuxCLI", "OmuxControlPlane", "OmuxCore"]
        ),
        .testTarget(
            name: "OmuxHooksTests",
            dependencies: ["OmuxHooks", "OmuxCore"]
        ),
        .testTarget(
            name: "OmuxAppShellTests",
            dependencies: ["OmuxAppShell", "OmuxTerminalBridge", "OmuxCore", "OmuxHooks"]
        ),
    ]
)

let package = Package(
    name: "OpenMUX",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "OmuxCore", targets: ["OmuxCore"]),
        .library(name: "OmuxTerminalBridge", targets: ["OmuxTerminalBridge"]),
        .library(name: "OmuxControlPlane", targets: ["OmuxControlPlane"]),
        .library(name: "OmuxHooks", targets: ["OmuxHooks"]),
        .library(name: "OmuxCLI", targets: ["OmuxCLI"]),
        .library(name: "OmuxAppShell", targets: ["OmuxAppShell"]),
        .executable(name: "OpenMUXApp", targets: ["OpenMUXApp"]),
        .executable(name: "omux", targets: ["omux"]),
    ],
    targets: targets
)
