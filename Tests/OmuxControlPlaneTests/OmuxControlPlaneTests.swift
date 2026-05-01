import Foundation
import XCTest
@testable import OmuxCore
@testable import OmuxControlPlane

final class OmuxControlPlaneTests: XCTestCase {
    func testJSONRPCRoundTripOverUnixSocket() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "control.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .object([
                "method": .string(request.method),
                "status": .string("ok"),
            ]))
        }
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        let response = try client.request(method: .listWorkspaces)

        XCTAssertEqual(
            response.result,
            .object([
                "method": .string(ControlMethod.listWorkspaces.rawValue),
                "status": .string("ok"),
            ])
        )
    }

    func testNewWorkspaceCommandsRoundTrip() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "workspace.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .object(["method": .string(request.method)]))
        }
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        let createTab = try client.request(method: .createTab)
        let split = try client.request(method: .splitPane)
        let splitDown = try client.request(method: .splitPane, params: .object([
            "axis": .string("rows"),
        ]))
        let createPaneTab = try client.request(method: .createPaneTab)
        let focusPaneTab = try client.request(method: .focusPaneTab, params: .object([
            "paneID": .string("pane-1"),
        ]))
        let closePaneTab = try client.request(method: .closePaneTab, params: .object([
            "paneID": .string("pane-1"),
        ]))
        let run = try client.request(method: .runCommand, params: .object([
            "sessionID": .string("session-1"),
            "command": .string("pwd"),
        ]))

        XCTAssertEqual(createTab.result, .object(["method": .string(ControlMethod.createTab.rawValue)]))
        XCTAssertEqual(split.result, .object(["method": .string(ControlMethod.splitPane.rawValue)]))
        XCTAssertEqual(splitDown.result, .object(["method": .string(ControlMethod.splitPane.rawValue)]))
        XCTAssertEqual(createPaneTab.result, .object(["method": .string(ControlMethod.createPaneTab.rawValue)]))
        XCTAssertEqual(focusPaneTab.result, .object(["method": .string(ControlMethod.focusPaneTab.rawValue)]))
        XCTAssertEqual(closePaneTab.result, .object(["method": .string(ControlMethod.closePaneTab.rawValue)]))
        XCTAssertEqual(run.result, .object(["method": .string(ControlMethod.runCommand.rawValue)]))
    }

    func testConfigCommandsRoundTrip() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "config.sock")
            .path(percentEncoded: false)

        let server = LocalControlServer(socketPath: socketPath)
        try server.start { request in
            JSONRPCResponse(id: request.id, result: .object(["method": .string(request.method)]))
        }
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        let doctor = try client.request(method: .configDoctor)
        let reload = try client.request(method: .configReload)

        XCTAssertEqual(doctor.result, .object(["method": .string(ControlMethod.configDoctor.rawValue)]))
        XCTAssertEqual(reload.result, .object(["method": .string(ControlMethod.configReload.rawValue)]))
    }

    func testControlPlaneEventSupportsSparseOpenMUXNativePayloads() {
        let event = ControlPlaneEvent(
            name: .notificationRaised,
            workspaceID: WorkspaceID(rawValue: "workspace-1"),
            payload: .object([
                "title": .string("Heads up"),
                "body": .string("Build finished"),
            ])
        )

        XCTAssertEqual(event.name, "notification.raised")
        XCTAssertEqual(
            event.rpcValue,
            .object([
                "name": .string("notification.raised"),
                "workspaceID": .string("workspace-1"),
                "tabID": .null,
                "paneID": .null,
                "sessionID": .null,
                "payload": .object([
                    "title": .string("Heads up"),
                    "body": .string("Build finished"),
                ]),
            ])
        )
    }

    func testTerminalEventUsesOpenMUXNativePayloads() {
        let event = ControlPlaneEvent(
            name: .commandFinished,
            workspaceID: WorkspaceID(rawValue: "workspace-1"),
            tabID: TabID(rawValue: "tab-1"),
            paneID: PaneID(rawValue: "pane-1"),
            sessionID: SessionID(rawValue: "session-1"),
            payload: .object([
                "exitCode": .integer(0),
                "durationNanoseconds": .integer(42),
            ])
        )

        XCTAssertEqual(event.name, "terminal.commandFinished")
        XCTAssertEqual(
            event.rpcValue,
            .object([
                "name": .string("terminal.commandFinished"),
                "workspaceID": .string("workspace-1"),
                "tabID": .string("tab-1"),
                "paneID": .string("pane-1"),
                "sessionID": .string("session-1"),
                "payload": .object([
                    "exitCode": .integer(0),
                    "durationNanoseconds": .integer(42),
                ]),
            ])
        )
    }

    func testTerminalEventStreamDeliversMixedNotifications() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "events.sock")
            .path(percentEncoded: false)

        let encoder = JSONEncoder()
        let server = LocalControlServer(socketPath: socketPath)
        try server.start(
            handler: { _ in
                JSONRPCResponse(id: nil, error: JSONRPCError(code: 404, message: "unexpected"))
            },
            streamHandler: { descriptor, request in
                guard request.method == ControlMethod.terminalEvents.rawValue else {
                    return false
                }

                let ack = JSONRPCResponse(id: request.id, result: .string("subscribed"))
                try UnixSocketIO.writeLine(try encoder.encode(ack), to: descriptor)

                let cwdEvent = JSONRPCRequest(
                    id: nil,
                    method: ControlMethod.terminalEvents.rawValue,
                    params: .object([
                        "name": .string("terminal.cwdChanged"),
                        "workspaceID": .string("workspace-1"),
                        "tabID": .string("tab-1"),
                        "paneID": .string("pane-1"),
                        "sessionID": .string("session-1"),
                        "payload": .object(["path": .string("/tmp/demo")]),
                    ])
                )
                try UnixSocketIO.writeLine(try encoder.encode(cwdEvent), to: descriptor)

                let finishedEvent = JSONRPCRequest(
                    id: nil,
                    method: ControlMethod.terminalEvents.rawValue,
                    params: .object([
                        "name": .string("workspace.opened"),
                        "workspaceID": .string("workspace-1"),
                        "tabID": .null,
                        "paneID": .null,
                        "sessionID": .null,
                        "payload": .object(["path": .string("/tmp/demo")]),
                    ])
                )
                try UnixSocketIO.writeLine(try encoder.encode(finishedEvent), to: descriptor)
                return true
            }
        )
        defer { server.stop() }

        let client = OmuxControlClient(socketPath: socketPath)
        var receivedEvents: [RPCValue] = []

        try client.streamTerminalEvents { event in
            receivedEvents.append(event)
        }

        XCTAssertEqual(receivedEvents.count, 2)
        XCTAssertEqual(receivedEvents[0].objectValue?["name"], .string("terminal.cwdChanged"))
        XCTAssertEqual(receivedEvents[1].objectValue?["name"], .string("workspace.opened"))
    }
}

private extension RPCValue {
    var objectValue: [String: RPCValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }
}
