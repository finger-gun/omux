// swift-tools-version: 6.0
import Foundation
import PackageDescription

let ghosttyXCFrameworkPath = "Vendor/ghostty/macos/GhosttyKit.xcframework"
guard FileManager.default.fileExists(atPath: ghosttyXCFrameworkPath) else {
    fatalError("Missing \(ghosttyXCFrameworkPath). Run `make setup` before building OpenMUX.")
}

var targets: [Target] = [
    .target(name: "OmuxCore"),
    .target(name: "OmuxConfig", dependencies: ["OmuxCore"]),
    .target(
        name: "OmuxTheme",
        dependencies: ["OmuxConfig"],
        resources: [
            .process("Resources"),
        ]
    ),
    .binaryTarget(
        name: "GhosttyKit",
        path: ghosttyXCFrameworkPath
    ),
    .target(
        name: "CGhostty",
        dependencies: ["GhosttyKit"],
        path: "Sources/CGhostty"
    )
]

targets.append(
    .target(
        name: "OmuxTerminalBridge",
        dependencies: ["OmuxCore", "OmuxConfig", "CGhostty", "GhosttyKit"],
        linkerSettings: [
            .linkedLibrary("c++"),
            .linkedFramework("Carbon"),
        ]
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
            dependencies: ["OmuxControlPlane", "OmuxCore", "OmuxConfig", "OmuxTheme"],
            path: "Sources/OmuxCLI"
        ),
        .target(
            name: "OmuxAppShell",
            dependencies: [
                "OmuxCore",
                "OmuxConfig",
                "OmuxTheme",
                "OmuxTerminalBridge",
                "OmuxControlPlane",
                "OmuxHooks",
            ],
            resources: [
                .process("Resources"),
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
            name: "OmuxConfigTests",
            dependencies: ["OmuxConfig"]
        ),
        .testTarget(
            name: "OmuxThemeTests",
            dependencies: ["OmuxTheme", "OmuxConfig"]
        ),
        .testTarget(
            name: "OmuxCoreTests",
            dependencies: ["OmuxCore"]
        ),
        .testTarget(
            name: "OmuxTerminalBridgeTests",
            dependencies: ["OmuxTerminalBridge", "OmuxCore", "OmuxConfig", "OmuxTheme"]
        ),
        .testTarget(
            name: "OmuxControlPlaneTests",
            dependencies: ["OmuxControlPlane", "OmuxCore"]
        ),
        .testTarget(
            name: "OmuxCLITests",
            dependencies: ["OmuxCLI", "OmuxControlPlane", "OmuxCore", "OmuxConfig"]
        ),
        .testTarget(
            name: "OmuxHooksTests",
            dependencies: ["OmuxHooks", "OmuxCore"]
        ),
        .testTarget(
            name: "OmuxAppShellTests",
            dependencies: ["OmuxAppShell", "OmuxTerminalBridge", "OmuxCore", "OmuxHooks", "OmuxConfig", "OmuxTheme"]
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
        .library(name: "OmuxConfig", targets: ["OmuxConfig"]),
        .library(name: "OmuxTheme", targets: ["OmuxTheme"]),
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
