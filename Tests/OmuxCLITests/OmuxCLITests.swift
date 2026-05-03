import Foundation
import XCTest
@testable import OmuxCLI
@testable import OmuxConfig
@testable import OmuxControlPlane
@testable import OmuxCore
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

    func testCLIOpenAcceptsOptionalPath() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "open.sock")
            .path(percentEncoded: false)
        let requests = LockedValue<[JSONRPCRequest]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "open"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "open", "/tmp"]), 0)

        XCTAssertEqual(requests.value.map(\.method), [
            ControlMethod.openWorkspace.rawValue,
            ControlMethod.openWorkspace.rawValue,
        ])
        XCTAssertNil(requests.value[0].params)
        guard case .object(let params)? = requests.value[1].params,
              case .string("/tmp")? = params["path"] else {
            return XCTFail("expected explicit open path")
        }
        XCTAssertEqual(output, ["ok", "ok"])
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
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-next"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-prev"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-focus", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-tab-close", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-next"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane-prev"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "run", "session-1", "pwd"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "run", "--pane", "pane-1", "--", "echo", "hello"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "send-text", "--session", "session-1", "--", "hello", "world"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "sessions"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "session"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "panes"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "pane"]), 0)

        XCTAssertEqual(output, [
            "\(ControlMethod.createTab.rawValue):none",
            "\(ControlMethod.splitPane.rawValue):columns",
            "\(ControlMethod.splitPane.rawValue):rows",
            "\(ControlMethod.createPaneTab.rawValue):none",
            "\(ControlMethod.focusNextPaneTab.rawValue):none",
            "\(ControlMethod.focusPreviousPaneTab.rawValue):none",
            "\(ControlMethod.focusPaneTab.rawValue):none",
            "\(ControlMethod.closePaneTab.rawValue):none",
            "\(ControlMethod.focusNextPane.rawValue):none",
            "\(ControlMethod.focusPreviousPane.rawValue):none",
            "\(ControlMethod.runCommand.rawValue):none",
            "\(ControlMethod.runCommand.rawValue):none",
            "\(ControlMethod.sendText.rawValue):none",
            "\(ControlMethod.listSessions.rawValue):none",
            "\(ControlMethod.listSessions.rawValue):none",
            "\(ControlMethod.listPanes.rawValue):none",
            "\(ControlMethod.listPanes.rawValue):none",
        ])
    }

    func testCLIListFullRequestsDetailedWorkspaceTopology() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "list-full.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            let full: Bool
            if case .object(let params)? = request.params,
               case .bool(true)? = params["full"] {
                full = true
            } else {
                full = false
            }
            return JSONRPCResponse(id: request.id, result: .string("\(request.method):\(full)"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "list", "--full"]), 0)
        XCTAssertEqual(output, ["\(ControlMethod.listWorkspaces.rawValue):true"])
    }

    func testCLISplitAcceptsDirectionAndTargetInEitherOrder() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "split.sock")
            .path(percentEncoded: false)

        let requests = LockedValue<[RPCValue?]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append(request.params)
            return JSONRPCResponse(id: request.id, result: .string("ok"))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "split", "left", "--focused"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split", "--pane", "pane-1", "up"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "split", "sideways"]), 1)

        guard case .object(let leftParams)? = requests.value[0],
              case .object(let upParams)? = requests.value[1],
              case .object(let leftTarget)? = leftParams["target"],
              case .object(let upTarget)? = upParams["target"]
        else {
            return XCTFail("expected split params")
        }

        XCTAssertEqual(leftParams["axis"], .string(PaneSplitAxis.columns.rawValue))
        XCTAssertEqual(leftTarget["type"], .string("focused"))
        XCTAssertEqual(upParams["axis"], .string(PaneSplitAxis.rows.rawValue))
        XCTAssertEqual(upTarget["type"], .string("pane"))
        XCTAssertEqual(upTarget["id"], .string("pane-1"))
        XCTAssertEqual(output.last, "usage: omux split [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused] [left|right|up|down]")
    }

    func testCLIHistoryRequestsScopesAndFormatsHumanOutput() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "h.sock")
            .path(percentEncoded: false)

        let requests = LockedValue<[(method: String, params: RPCValue?)]>([])
        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            requests.value.append((request.method, request.params))
            return JSONRPCResponse(id: request.id, result: .object([
                "maxBytes": .integer(16_384),
                "maxLines": .integer(400),
                "items": .array([
                    .object([
                        "workspaceID": .string("workspace-1"),
                        "workspaceName": .string("OMUX"),
                        "tabID": .string("tab-1"),
                        "tabTitle": .string("Main"),
                        "paneStackID": .string("stack-1"),
                        "paneID": .string("pane-1"),
                        "paneTitle": .string("omux"),
                        "sessionID": .string("session-1"),
                        "workingDirectory": .string("/tmp/omux"),
                        "text": .string("hello\nworld"),
                        "lineCount": .integer(2),
                        "byteCount": .integer(11),
                        "truncated": .bool(false),
                        "unavailable": .null,
                    ]),
                ]),
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "pane-1"]), 0)
        XCTAssertEqual(command.run(arguments: ["omux", "history", "all", "--max-lines", "2", "--max-bytes", "50"]), 0)

        XCTAssertEqual(requests.value.map(\.method), Array(repeating: ControlMethod.terminalHistory.rawValue, count: 3))
        XCTAssertTrue(output.joined(separator: "\n").contains("== OMUX (workspace-1) / Main (tab-1) / omux (pane-1)"))
        XCTAssertTrue(output.joined(separator: "\n").contains("cwd: /tmp/omux"))
        XCTAssertTrue(output.joined(separator: "\n").contains("hello\nworld"))

        guard case .object(let noArgParams)? = requests.value[0].params,
              case .object(let paneParams)? = requests.value[1].params,
              case .object(let allParams)? = requests.value[2].params
        else {
            return XCTFail("expected history params")
        }
        XCTAssertEqual(noArgParams["scope"], .string("activeWorkspace"))
        XCTAssertEqual(paneParams["scope"], .string("pane"))
        XCTAssertEqual(paneParams["paneID"], .string("pane-1"))
        XCTAssertEqual(allParams["scope"], .string("all"))
        XCTAssertEqual(allParams["maxLines"], .integer(2))
        XCTAssertEqual(allParams["maxBytes"], .integer(50))
    }

    func testCLIHistorySupportsJSONOutputAndInvalidArguments() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "hj.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            XCTAssertEqual(request.method, ControlMethod.terminalHistory.rawValue)
            return JSONRPCResponse(id: request.id, result: .object([
                "items": .array([]),
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history", "--json", "all"]), 0)
        XCTAssertTrue(output.first?.contains("\"items\" : [") == true)

        output.removeAll()
        XCTAssertEqual(command.run(arguments: ["omux", "history", "--max-lines"]), 1)
        XCTAssertEqual(output, ["usage: omux history [--json] [--max-lines <count>] [--max-bytes <count>] [<pane-id>|all]"])
    }

    func testCLIHistoryPrintsUnavailablePane() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "hu.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .object([
                "items": .array([
                    .object([
                        "workspaceID": .string("workspace-1"),
                        "workspaceName": .string("OMUX"),
                        "tabID": .string("tab-1"),
                        "tabTitle": .string("Main"),
                        "paneStackID": .null,
                        "paneID": .string("pane-1"),
                        "paneTitle": .string("omux"),
                        "sessionID": .string("session-1"),
                        "workingDirectory": .null,
                        "text": .string(""),
                        "lineCount": .integer(0),
                        "byteCount": .integer(0),
                        "truncated": .bool(false),
                        "unavailable": .string("history unavailable"),
                    ]),
                ]),
            ]))
        }
        defer { server.stop() }

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "history", "pane-1"]), 0)
        XCTAssertTrue(output.contains("unavailable: history unavailable"))
        XCTAssertTrue(output.contains("(no history)"))
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
        var selectedInput: String?
        let command = OmuxCLICommand(
            client: OmuxControlClient(socketPath: socketPath),
            writeLine: { output.append($0) },
            readInputLine: {
                selectedInput = output
                    .first(where: { $0.contains(" nord — Nord") })?
                    .split(separator: ".", maxSplits: 1)
                    .first
                    .map(String.init)
                return selectedInput ?? ""
            }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme"]), 0)
        XCTAssertNotNil(selectedInput)
        let contents = try String(contentsOf: tempHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"nord\""))
        XCTAssertEqual(output.first, "Available themes:")
        XCTAssertTrue(output.contains("Select theme number or name:"))
        XCTAssertTrue(output.contains("Theme set to Nord."))
    }

    func testCLIInteractiveThemePickerSelectsThemeAndReloads() throws {
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
            .appending(path: "itp.sock")
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
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            isInteractiveThemePickerAvailable: { true },
            selectThemeInteractively: { themes, currentThemeName in
                XCTAssertEqual(currentThemeName, "monokai-soda")
                return themes.first(where: { $0.name == "nord" })
            }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme"]), 0)
        let contents = try String(contentsOf: tempHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"nord\""))
        XCTAssertEqual(output, ["Theme set to Nord.", "No diagnostics.", "OpenMUX config reloaded."])
    }

    func testCLIInteractiveThemePickerCancellationDoesNotModifyConfig() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer {
            unsetenv("OMUX_HOME")
            try? FileManager.default.removeItem(at: tempHome)
        }
        setenv("OMUX_HOME", tempHome.path, 1)
        let configURL = tempHome.appendingPathComponent("config.toml")
        try OmuxConfigTemplate.starter(themeName: "monokai-soda").write(
            to: configURL,
            atomically: true,
            encoding: .utf8
        )

        var output = [String]()
        let command = OmuxCLICommand(
            client: OmuxControlClient(),
            writeLine: { output.append($0) },
            readInputLine: { nil },
            configLoader: OmuxConfigLoader(),
            themeRegistry: OmuxThemeRegistry(),
            installer: OmuxCLIInstaller(),
            isInteractiveThemePickerAvailable: { true },
            selectThemeInteractively: { _, _ in nil }
        )

        XCTAssertEqual(command.run(arguments: ["omux", "theme"]), 0)
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("name = \"monokai-soda\""))
        XCTAssertEqual(output, ["Cancelled."])
    }

    func testInteractiveThemePickerViewportKeepsSelectedThemeVisible() {
        let viewport = ThemePickerViewport.make(itemCount: 28, selectedIndex: 17, terminalRows: 8)

        XCTAssertLessThanOrEqual(viewport.startIndex, 17)
        XCTAssertLessThan(17, viewport.endIndex)
        XCTAssertEqual(viewport.visibleCount, 6)
        XCTAssertEqual(viewport.endIndex - viewport.startIndex, 6)
    }

    func testInteractiveThemePickerViewportClampsNearEnd() {
        let viewport = ThemePickerViewport.make(itemCount: 28, selectedIndex: 27, terminalRows: 8)

        XCTAssertEqual(viewport.startIndex, 22)
        XCTAssertEqual(viewport.endIndex, 28)
        XCTAssertEqual(viewport.visibleCount, 6)
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

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
