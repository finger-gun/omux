import Foundation
import OmuxControlPlane
import OmuxCore

final class OpenMUXControlPlaneService {
    private let controller: WorkspaceController
    private let server: LocalControlServer

    init(
        controller: WorkspaceController,
        socketPath: String = ControlPlaneSocket.defaultPath()
    ) {
        self.controller = controller
        self.server = LocalControlServer(socketPath: socketPath)
    }

    func start() throws {
        try server.start { [controller] request in
            do {
                return try Self.handle(request: request, controller: controller)
            } catch {
                return JSONRPCResponse(
                    id: request.id,
                    error: JSONRPCError(code: -32001, message: String(describing: error))
                )
            }
        }
    }

    func stop() {
        server.stop()
    }

    private static func handle(request: JSONRPCRequest, controller: WorkspaceController) throws -> JSONRPCResponse {
        switch ControlMethod(rawValue: request.method) {
        case .openWorkspace:
            let path = request.params?.objectValue?["path"]?.stringValue ?? FileManager.default.currentDirectoryPath
            let workspace = try controller.openWorkspace(at: path)
            return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
        case .listWorkspaces:
            let workspaces = controller.listWorkspaces()
            return JSONRPCResponse(
                id: request.id,
                result: .array(workspaces.map { .object($0.rpcObject) })
            )
        case .createTab:
            if let workspace = try controller.createTab() {
                return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "no active workspace"))
        case .splitPane:
            let axisRawValue = request.params?.objectValue?["axis"]?.stringValue
            let axis = axisRawValue.flatMap(PaneSplitAxis.init(rawValue:)) ?? .columns
            if let workspace = try controller.splitFocusedPane(axis: axis) {
                return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "no active pane"))
        case .createPaneTab:
            if let workspace = try controller.createPaneTab() {
                return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "no active pane stack"))
        case .focusPaneTab:
            let paneID = request.params?.objectValue?["paneID"]?.stringValue ?? ""
            if let workspace = controller.focusPaneTab(paneID: PaneID(rawValue: paneID)) {
                return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "pane tab not found"))
        case .closePaneTab:
            let paneID = request.params?.objectValue?["paneID"]?.stringValue.map(PaneID.init(rawValue:))
            if let workspace = try controller.closePaneTab(paneID: paneID) {
                return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 409, message: "pane tab cannot be closed"))
        case .focusSession:
            let sessionID = request.params?.objectValue?["sessionID"]?.stringValue ?? ""
            let focused = try controller.focus(sessionID: SessionID(rawValue: sessionID))
            return JSONRPCResponse(id: request.id, result: .bool(focused))
        case .runCommand:
            let sessionID = request.params?.objectValue?["sessionID"]?.stringValue ?? ""
            let command = request.params?.objectValue?["command"]?.stringValue ?? ""
            let didRun = try controller.runCommand(in: SessionID(rawValue: sessionID), command: command)
            return JSONRPCResponse(id: request.id, result: .bool(didRun))
        case .sendNotification:
            let title = request.params?.objectValue?["title"]?.stringValue ?? "OpenMUX"
            let body = request.params?.objectValue?["body"]?.stringValue ?? ""
            try controller.notify(NotificationRequest(title: title, body: body))
            return JSONRPCResponse(id: request.id, result: .string("notification queued"))
        case .restoreLayout:
            let workspaceID = request.params?.objectValue?["workspaceID"]?.stringValue ?? ""
            if let workspace = controller.restore(workspaceID: WorkspaceID(rawValue: workspaceID)) {
                return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "workspace not found"))
        case .none:
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32601, message: "method not found"))
        }
    }
}

private extension RPCValue {
    var objectValue: [String: RPCValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

private extension Workspace {
    var rpcObject: [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "name": .string(name),
            "rootPath": .string(rootPath),
            "tabCount": .integer(tabs.count),
            "paneCount": .integer(tabs.reduce(into: 0) { $0 += $1.panes.count }),
            "focusedPaneID": focusedPane.map { .string($0.id.rawValue) } ?? .null,
            "focusedPaneStackID": focusedPaneStack.map { .string($0.id.rawValue) } ?? .null,
            "focusedSessionID": focusedPane.map { .string($0.session.id.rawValue) } ?? .null,
        ]
    }
}

private extension WorkspaceSummary {
    var rpcObject: [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "name": .string(name),
            "rootPath": .string(rootPath),
            "tabCount": .integer(tabCount),
            "paneCount": .integer(paneCount),
        ]
    }
}
