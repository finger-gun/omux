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
        let sendText = try client.request(method: .sendText, params: .object([
            "target": .object(["type": .string("pane"), "id": .string("pane-1")]),
            "text": .string("hello"),
        ]))
        let sessions = try client.request(method: .listSessions)
        let panes = try client.request(method: .listPanes)
        let history = try client.request(method: .terminalHistory, params: .object([
            "scope": .string("pane"),
            "id": .string("pane-1"),
        ]))

        XCTAssertEqual(createTab.result, .object(["method": .string(ControlMethod.createTab.rawValue)]))
        XCTAssertEqual(split.result, .object(["method": .string(ControlMethod.splitPane.rawValue)]))
        XCTAssertEqual(splitDown.result, .object(["method": .string(ControlMethod.splitPane.rawValue)]))
        XCTAssertEqual(createPaneTab.result, .object(["method": .string(ControlMethod.createPaneTab.rawValue)]))
        XCTAssertEqual(focusPaneTab.result, .object(["method": .string(ControlMethod.focusPaneTab.rawValue)]))
        XCTAssertEqual(closePaneTab.result, .object(["method": .string(ControlMethod.closePaneTab.rawValue)]))
        XCTAssertEqual(run.result, .object(["method": .string(ControlMethod.runCommand.rawValue)]))
        XCTAssertEqual(sendText.result, .object(["method": .string(ControlMethod.sendText.rawValue)]))
        XCTAssertEqual(sessions.result, .object(["method": .string(ControlMethod.listSessions.rawValue)]))
        XCTAssertEqual(panes.result, .object(["method": .string(ControlMethod.listPanes.rawValue)]))
        XCTAssertEqual(history.result, .object(["method": .string(ControlMethod.terminalHistory.rawValue)]))
    }

    func testTerminalHistoryRequestParsesScopesAndBounds() {
        XCTAssertEqual(ControlPlaneHistoryRequest(rpcValue: nil), ControlPlaneHistoryRequest())

        XCTAssertEqual(
            ControlPlaneHistoryRequest(rpcValue: .object([
                "scope": .string("all"),
                "maxLines": .integer(20),
                "maxBytes": .integer(1_024),
            ])),
            ControlPlaneHistoryRequest(scope: .all, maxBytes: 1_024, maxLines: 20)
        )

        XCTAssertEqual(
            ControlPlaneHistoryRequest(rpcValue: .object([
                "paneID": .string("pane-1"),
                "maxLines": .integer(2),
                "maxBytes": .integer(128),
            ])),
            ControlPlaneHistoryRequest(scope: .pane(PaneID(rawValue: "pane-1")), maxBytes: 128, maxLines: 2)
        )

        XCTAssertNil(ControlPlaneHistoryRequest(rpcValue: .object(["scope": .string("bogus")])))
    }

    func testTerminalHistoryResponseUsesOpenMUXNativeMetadata() {
        let response = ControlPlaneHistoryResponse(
            scope: .pane(PaneID(rawValue: "pane-1")),
            maxBytes: 1_000,
            maxLines: 10,
            items: [
                ControlPlanePaneHistoryItem(
                    workspaceID: WorkspaceID(rawValue: "workspace-1"),
                    workspaceName: "OMUX",
                    tabID: TabID(rawValue: "tab-1"),
                    tabTitle: "Main",
                    paneStackID: PaneStackID(rawValue: "stack-1"),
                    paneID: PaneID(rawValue: "pane-1"),
                    paneTitle: "omux",
                    sessionID: SessionID(rawValue: "session-1"),
                    workingDirectory: "/tmp/omux",
                    text: "one\ntwo",
                    truncated: true
                ),
            ]
        )

        guard case .object(let object) = response.rpcValue,
              case .array(let items)? = object["items"],
              case .object(let item)? = items.first
        else {
            return XCTFail("expected structured history response")
        }

        XCTAssertEqual(item["workspaceID"], .string("workspace-1"))
        XCTAssertEqual(item["workspaceName"], .string("OMUX"))
        XCTAssertEqual(item["tabID"], .string("tab-1"))
        XCTAssertEqual(item["paneStackID"], .string("stack-1"))
        XCTAssertEqual(item["paneID"], .string("pane-1"))
        XCTAssertEqual(item["sessionID"], .string("session-1"))
        XCTAssertEqual(item["workingDirectory"], .string("/tmp/omux"))
        XCTAssertEqual(item["text"], .string("one\ntwo"))
        XCTAssertEqual(item["lineCount"], .integer(2))
        XCTAssertEqual(item["byteCount"], .integer(7))
        XCTAssertEqual(item["truncated"], .bool(true))
        XCTAssertEqual(item["unavailable"], .null)
    }

    func testTerminalTargetSelectorsRoundTripFromRPCValues() {
        XCTAssertEqual(
            ControlPlaneTerminalTarget(rpcValue: .object(["sessionID": .string("session-1")])),
            .session(SessionID(rawValue: "session-1"))
        )
        XCTAssertEqual(
            ControlPlaneTerminalTarget(rpcValue: .object(["target": .object(["type": .string("pane"), "id": .string("pane-1")])])),
            .pane(PaneID(rawValue: "pane-1"))
        )
        XCTAssertEqual(
            ControlPlaneTerminalTarget(rpcValue: .object(["target": .object(["type": .string("tab"), "id": .string("tab-1")])])),
            .tab(TabID(rawValue: "tab-1"))
        )
        XCTAssertEqual(
            ControlPlaneTerminalTarget(rpcValue: .object(["target": .object(["type": .string("workspace"), "id": .string("workspace-1")])])),
            .workspace(WorkspaceID(rawValue: "workspace-1"))
        )
        XCTAssertEqual(
            ControlPlaneTerminalTarget(rpcValue: .object(["focused": .bool(true)])),
            .focused
        )
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

    func testLongLivedEventStreamDoesNotBlockRequests() throws {
        let socketPath = "/tmp/omux-\(UUID().uuidString.prefix(8)).sock"

        let encoder = JSONEncoder()
        let streamConnected = DispatchSemaphore(value: 0)
        let releaseStream = DispatchSemaphore(value: 0)
        let server = LocalControlServer(socketPath: socketPath)
        try server.start(
            handler: { request in
                JSONRPCResponse(id: request.id, result: .object(["method": .string(request.method)]))
            },
            streamHandler: { descriptor, request in
                guard request.method == ControlMethod.terminalEvents.rawValue else {
                    return false
                }

                let ack = JSONRPCResponse(id: request.id, result: .string("subscribed"))
                try UnixSocketIO.writeLine(try encoder.encode(ack), to: descriptor)
                streamConnected.signal()
                _ = releaseStream.wait(timeout: .now() + 2)
                return true
            }
        )
        defer { server.stop() }

        let streamFinished = expectation(description: "stream exits")
        DispatchQueue.global().async {
            let client = OmuxControlClient(socketPath: socketPath)
            try? client.streamTerminalEvents { _ in }
            streamFinished.fulfill()
        }

        XCTAssertEqual(streamConnected.wait(timeout: .now() + 2), .success)

        let client = OmuxControlClient(socketPath: socketPath)
        let response = try client.request(method: .listWorkspaces)

        XCTAssertEqual(response.result, .object(["method": .string(ControlMethod.listWorkspaces.rawValue)]))
        releaseStream.signal()
        wait(for: [streamFinished], timeout: 2)
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
