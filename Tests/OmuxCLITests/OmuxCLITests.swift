import Foundation
import XCTest
@testable import OmuxCLI
@testable import OmuxConfig
@testable import OmuxControlPlane
@testable import OmuxTheme

final class OmuxCLITests: XCTestCase {
    func testCLIUsesPublicControlPlane() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "cli.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            switch request.method {
            case ControlMethod.listWorkspaces.rawValue:
                return JSONRPCResponse(id: request.id, result: .array([
                    .object([
                        "id": .string("workspace-1"),
                        "name": .string("demo"),
                        "rootPath": .string("/tmp/demo"),
                    ]),
                ]))
            default:
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
            }
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "list"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.count, 1)
        XCTAssertTrue(output[0].contains("demo"))
        XCTAssertTrue(output[0].contains("/tmp/demo"))
    }

    func testCLISupportsTabSplitAndRunCommands() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "commands.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            let axis = request.params.flatMap {
                if case .object(let object) = $0, case .string(let axis)? = object["axis"] {
                    return axis
                }
                return nil
            } ?? "none"
            return JSONRPCResponse(id: request.id, result: .string("\(request.method):\(axis)"))
        }
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        var output = [String]()
        let command = OmuxCLICommand(client: client, writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "tab"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split", "down"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-focus", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-close", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "run", "session-1", "pwd"]), 0)

        XCTAssertEqual(output, [
            "\(ControlMethod.createTab.rawValue):none",
            "\(ControlMethod.splitPane.rawValue):columns",
            "\(ControlMethod.splitPane.rawValue):rows",
            "\(ControlMethod.createPaneTab.rawValue):none",
            "\(ControlMethod.focusPaneTab.rawValue):none",
            "\(ControlMethod.closePaneTab.rawValue):none",
            "\(ControlMethod.runCommand.rawValue):none",
        ])
    }

    func testCLIPrintsControlPlaneEventsUntilStreamCloses() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "events.sock")
            .path(percentEncoded: false)

        let encoder = JSONEncoder()
        let server = LocalControlServer(socketPath: socketPath)
        try server.start(
            handler: { request in
                JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
            },
            streamHandler: { descriptor, request in
                guard request.method == ControlMethod.terminalEvents.rawValue else {
                    return false
                }

                let ack = JSONRPCResponse(id: request.id, result: .string("subscribed"))
                try UnixSocketIO.writeLine(try encoder.encode(ack), to: descriptor)

                let event = JSONRPCRequest(
                    id: nil,
                    method: ControlMethod.terminalEvents.rawValue,
                    params: .object([
                        "name": .string("workspace.opened"),
                        "workspaceID": .string("workspace-1"),
                        "tabID": .null,
                        "paneID": .null,
                        "sessionID": .null,
                        "payload": .object([
                            "path": .string("/tmp/demo"),
                        ]),
                    ])
                )
                try UnixSocketIO.writeLine(try encoder.encode(event), to: descriptor)
                return true
            }
        )
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "events"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output.count, 1)
        XCTAssertTrue(output[0].contains("\"name\" : \"workspace.opened\""))
        XCTAssertTrue(output[0].contains("\"workspaceID\" : \"workspace-1\""))
    }

    func testCLIConfigDoctorPrintsWarningsAndReturnsZero() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "doctor.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configDoctor.rawValue {
                return JSONRPCResponse(id: request.id, result: .array([
                    .object([
                        "severity": .string("warning"),
                        "message": .string("managed key overridden"),
                        "filePath": .string("/tmp/config.toml"),
                        "line": .integer(12),
                    ]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "config", "doctor"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output, ["[warning] /tmp/config.toml:12 managed key overridden"])
    }

    func testCLIConfigReloadPrintsResult() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "reload.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        let exitCode = command.run(arguments: ["omux", "config", "reload"])

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(output, ["No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIConfigInitWritesStarterConfigAndRefusesOverwrite() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "config", "init"]), 0)
        let configURL = tempHome.appendingPathComponent("config.toml")
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("schema = 1"))
        XCTAssertTrue(contents.contains("[theme]"))

        output.removeAll()
        XCTAssertEqual(command.run(arguments: ["omux", "config", "init"]), 1)
        XCTAssertEqual(output, ["omux error: \(configURL.path) already exists"])
    }

    func testCLIThemeListPrintsAvailableThemesAndCurrentTheme() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        try OmuxConfigTemplate.starter(themeName: "nord").write(
            to: tempHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        var output = [String]()
        let command = OmuxCLICommand(writeLine: { output.append($0) })

        XCTAssertEqual(command.run(arguments: ["omux", "theme", "list"]), 0)
        XCTAssertEqual(output.first, "Available themes:")
        XCTAssertTrue(output.contains(where: { $0.contains("* nord — Nord") }))
        XCTAssertTrue(output.contains(where: { $0.contains("monokai-soda") }))
    }

    func testCLIThemeSetUpdatesConfigAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        try OmuxConfigTemplate.starter(themeName: "monokai-soda").write(
            to: tempHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "theme-reload.sock")
            .path(percentEncoded: false)
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme", "nord"]), 0)
        let contents = try String(contentsOf: tempHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"nord\""))
        XCTAssertEqual(output, ["Theme set to Nord.", "No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIThemePickerSelectsThemeByNumberAndReloads() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        try OmuxConfigTemplate.starter(themeName: "monokai-soda").write(
            to: tempHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "theme-picker.sock")
            .path(percentEncoded: false)
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            if request.method == ControlMethod.configReload.rawValue {
                return JSONRPCResponse(id: request.id, result: .object([
                    "applied": .bool(true),
                    "diagnostics": .array([]),
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "unexpected"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: { "5" }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme"]), 0)
        let contents = try String(contentsOf: tempHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"nord\""))
        XCTAssertEqual(output.first, "Available themes:")
        XCTAssertTrue(output.contains("Select theme number or name:"))
        XCTAssertTrue(output.contains("Theme set to Nord."))
    }

    func testCLIInstallCommandCreatesSymlinkAndPrintsPathHintWhenNeeded() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempHome = tempRoot.appendingPathComponent("home", isDirectory: true)
        let binDirectory = tempHome
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let executableURL = tempRoot.appendingPathComponent("OpenMUX.app/Contents/MacOS/omux", isDirectory: false)

        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(
                environment: ["PATH": "/usr/bin:/bin"],
                executablePath: executableURL.path,
                homeDirectoryURL: tempHome
            )
        )

        XCTAssertEqual(command.run(arguments: ["omux", "install-cli"]), 0)

        let installedURL = binDirectory.appendingPathComponent("omux", isDirectory: false)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: installedURL.path), executableURL.path)
        XCTAssertEqual(output[0], "Installed omux at \(installedURL.path) -> \(executableURL.path)")
        XCTAssertEqual(output[1], "Add this to your shell profile: export PATH=\"\(binDirectory.path):$PATH\"")
    }

    func testCLIInstallCommandSupportsExplicitDestination() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installDirectory = tempRoot.appendingPathComponent("bin", isDirectory: true)
        let executableURL = tempRoot.appendingPathComponent("OpenMUX.app/Contents/MacOS/omux", isDirectory: false)

        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let destinationURL = installDirectory.appendingPathComponent("omux", isDirectory: false)
        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(
                environment: ["PATH": "\(installDirectory.path):/usr/bin:/bin"],
                executablePath: executableURL.path,
                homeDirectoryURL: tempRoot
            )
        )

        XCTAssertEqual(command.run(arguments: ["omux", "install-cli", destinationURL.path]), 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destinationURL.path), executableURL.path)
        XCTAssertEqual(output, ["Installed omux at \(destinationURL.path) -> \(executableURL.path)"])
    }
}
