import Foundation
import OmuxControlPlane
import OmuxConfig
import OmuxCore

final class OpenMUXControlPlaneService: @unchecked Sendable {
    private final class TerminalEventSubscription {
        private let lock = NSLock()
        private let condition = NSCondition()
        private var queue: [ControlPlaneTerminalEvent] = []
        private var cancelled = false

        func push(_ event: ControlPlaneTerminalEvent) {
            lock.lock()
            let isCancelled = cancelled
            lock.unlock()
            guard isCancelled == false else {
                return
            }

            condition.lock()
            queue.append(event)
            condition.signal()
            condition.unlock()
        }

        func nextEvent(timeout: TimeInterval = 0.5) -> ControlPlaneTerminalEvent? {
            condition.lock()
            defer { condition.unlock() }

            while queue.isEmpty && cancelled == false {
                guard condition.wait(until: Date().addingTimeInterval(timeout)) else {
                    return nil
                }
            }

            guard queue.isEmpty == false else {
                return nil
            }

            return queue.removeFirst()
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()

            condition.lock()
            condition.broadcast()
            condition.unlock()
        }
    }

    private final class TerminalEventBroadcaster {
        private let lock = NSLock()
        private var subscriptions: [UUID: TerminalEventSubscription] = [:]

        func subscribe() -> (id: UUID, subscription: TerminalEventSubscription) {
            let id = UUID()
            let subscription = TerminalEventSubscription()
            lock.lock()
            subscriptions[id] = subscription
            lock.unlock()
            return (id, subscription)
        }

        func unsubscribe(_ id: UUID) {
            lock.lock()
            let subscription = subscriptions.removeValue(forKey: id)
            lock.unlock()
            subscription?.cancel()
        }

        func publish(_ event: ControlPlaneTerminalEvent) {
            lock.lock()
            let activeSubscriptions = Array(subscriptions.values)
            lock.unlock()

            for subscription in activeSubscriptions {
                subscription.push(event)
            }
        }
    }

    private let controller: WorkspaceController
    private let configurationCoordinator: OpenMUXConfigurationCoordinator
    private let server: LocalControlServer
    private let terminalEventBroadcaster = TerminalEventBroadcaster()

    init(
        controller: WorkspaceController,
        configurationCoordinator: OpenMUXConfigurationCoordinator,
        socketPath: String = ControlPlaneSocket.defaultPath()
    ) {
        self.controller = controller
        self.configurationCoordinator = configurationCoordinator
        self.server = LocalControlServer(socketPath: socketPath)
    }

    func start() throws {
        let previousTerminalEventHandler = controller.onTerminalEvent
        controller.onTerminalEvent = { [weak self] event in
            previousTerminalEventHandler?(event)
            self?.terminalEventBroadcaster.publish(event)
        }

        try server.start(
            handler: { [weak self] request in
                guard let self else {
                    return JSONRPCResponse(
                        id: request.id,
                        error: JSONRPCError(code: -32001, message: "control plane unavailable")
                    )
                }
                do {
                    return try self.handle(request: request)
                } catch {
                    return JSONRPCResponse(
                        id: request.id,
                        error: JSONRPCError(code: -32001, message: String(describing: error))
                    )
                }
            },
            streamHandler: { [weak self] descriptor, request in
                guard let self else {
                    return false
                }
                return try self.handleStream(descriptor: descriptor, request: request)
            }
        )
    }

    func stop() {
        server.stop()
    }

    private func handle(request: JSONRPCRequest) throws -> JSONRPCResponse {
        try mainActorSyncThrowing {
            try handleOnMain(request: request)
        }
    }

    @MainActor
    private func handleOnMain(request: JSONRPCRequest) throws -> JSONRPCResponse {
        switch ControlMethod(rawValue: request.method) {
        case .openWorkspace:
            let rawPath = request.params?.objectValue?["path"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let workspace: Workspace
            if let rawPath, rawPath.isEmpty == false {
                workspace = try controller.openWorkspace(at: OmuxWorkspacePathResolver.resolve(rawPath) ?? rawPath)
            } else {
                workspace = try controller.createWorkspace()
            }
            return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
        case .closeWorkspace:
            let workspaceID = request.params?.objectValue?["workspaceID"]?.stringValue.map(WorkspaceID.init(rawValue:))
            let updatedWorkspace: Workspace?
            if let workspaceID {
                updatedWorkspace = try controller.closeWorkspace(workspaceID)
            } else {
                updatedWorkspace = try controller.deleteActiveWorkspace()
            }
            if let updatedWorkspace {
                return JSONRPCResponse(
                    id: request.id,
                    result: ControlPlaneActionResult(
                        workspace: .object(updatedWorkspace.rpcObject)
                    ).rpcValue
                )
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 409, message: "workspace cannot be closed"))
        case .listWorkspaces:
            if request.params?.objectValue?["full"]?.boolValue == true {
                let workspaces = controller.allWorkspaces()
                return JSONRPCResponse(id: request.id, result: .array(workspaces.map { .object($0.rpcObject) }))
            } else {
                let workspaces = controller.listWorkspaces()
                return JSONRPCResponse(
                    id: request.id,
                    result: .array(workspaces.map { .object($0.rpcObject) })
                )
            }
        case .createTab:
            if let workspace = try controller.createTab() {
                let created = workspace.focusedPane.map {
                    ControlPlaneTerminalContext(
                        workspaceID: workspace.id,
                        tabID: workspace.focusedTabID,
                        paneStackID: workspace.focusedPaneStack?.id,
                        paneID: $0.id,
                        sessionID: $0.session.id
                    )
                }
                return JSONRPCResponse(
                    id: request.id,
                    result: ControlPlaneActionResult(
                        target: created,
                        created: created,
                        workspace: .object(workspace.rpcObject)
                    ).rpcValue
                )
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "no active workspace"))
        case .splitPane:
            let axisRawValue = request.params?.objectValue?["axis"]?.stringValue
            let axis = axisRawValue.flatMap(PaneSplitAxis.init(rawValue:)) ?? .columns
            let target = ControlPlaneTerminalTarget(rpcValue: request.params)
            if let result = try controller.splitPane(target: target, axis: axis) {
                return JSONRPCResponse(
                    id: request.id,
                    result: ControlPlaneActionResult(
                        target: result.created,
                        created: result.created,
                        workspace: .object(result.workspace.rpcObject),
                        extra: ["axis": .string(axis.rawValue)]
                    ).rpcValue
                )
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target pane not found"))
        case .removePane:
            let target = ControlPlaneTerminalTarget(rpcValue: request.params) ?? .focused
            guard let context = controller.resolveTerminalTarget(target) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target pane not found"))
            }
            if target != .focused {
                guard try controller.focus(target: target) != nil else {
                    return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target pane not found"))
                }
            }
            guard let workspace = try controller.removeActivePane() else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 409, message: "pane cannot be removed"))
            }
            return JSONRPCResponse(
                id: request.id,
                result: ControlPlaneActionResult(
                    target: context,
                    workspace: .object(workspace.rpcObject)
                ).rpcValue
            )
        case .createPaneTab:
            if let workspace = try controller.createPaneTab() {
                let created = workspace.focusedPane.map {
                    ControlPlaneTerminalContext(
                        workspaceID: workspace.id,
                        tabID: workspace.focusedTabID,
                        paneStackID: workspace.focusedPaneStack?.id,
                        paneID: $0.id,
                        sessionID: $0.session.id
                    )
                }
                return JSONRPCResponse(
                    id: request.id,
                    result: ControlPlaneActionResult(
                        target: created,
                        created: created,
                        workspace: .object(workspace.rpcObject)
                    ).rpcValue
                )
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "no active pane stack"))
        case .focusPaneTab:
            let paneID = request.params?.objectValue?["paneID"]?.stringValue ?? ""
            if let workspace = controller.focusPaneTab(paneID: PaneID(rawValue: paneID)) {
                let context = controller.resolveTerminalTarget(.pane(PaneID(rawValue: paneID)))
                return JSONRPCResponse(
                    id: request.id,
                    result: ControlPlaneActionResult(
                        target: context,
                        workspace: .object(workspace.rpcObject)
                    ).rpcValue
                )
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "pane tab not found"))
        case .focusNextPaneTab:
            return navigationResponse(
                id: request.id,
                workspace: controller.focusNextPaneTab(),
                unavailableMessage: "next pane tab unavailable"
            )
        case .focusPreviousPaneTab:
            return navigationResponse(
                id: request.id,
                workspace: controller.focusPreviousPaneTab(),
                unavailableMessage: "previous pane tab unavailable"
            )
        case .closePaneTab:
            let paneID = request.params?.objectValue?["paneID"]?.stringValue.map(PaneID.init(rawValue:))
            if let workspace = try controller.closePaneTab(paneID: paneID) {
                return JSONRPCResponse(id: request.id, result: .object(workspace.rpcObject))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 409, message: "pane tab cannot be closed"))
        case .focusNextPane:
            return navigationResponse(
                id: request.id,
                workspace: controller.focusNextPane(),
                unavailableMessage: "next pane unavailable"
            )
        case .focusPreviousPane:
            return navigationResponse(
                id: request.id,
                workspace: controller.focusPreviousPane(),
                unavailableMessage: "previous pane unavailable"
            )
        case .focusSession:
            guard let target = ControlPlaneTerminalTarget(rpcValue: request.params) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing target"))
            }
            guard let context = try controller.focus(target: target) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target not found"))
            }
            return JSONRPCResponse(id: request.id, result: ControlPlaneActionResult(target: context).rpcValue)
        case .runCommand:
            let command = request.params?.objectValue?["command"]?.stringValue ?? ""
            guard let target = ControlPlaneTerminalTarget(rpcValue: request.params), command.isEmpty == false else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing target or command"))
            }
            guard let result = try controller.runCommand(target: target, command: command) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target not found"))
            }
            return JSONRPCResponse(id: request.id, result: result.rpcValue)
        case .sendText:
            let text = request.params?.objectValue?["text"]?.stringValue ?? ""
            guard let target = ControlPlaneTerminalTarget(rpcValue: request.params) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing target"))
            }
            guard let result = try controller.sendText(target: target, text: text) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target not found"))
            }
            return JSONRPCResponse(id: request.id, result: result.rpcValue)
        case .listSessions:
            return JSONRPCResponse(id: request.id, result: .array(controller.allWorkspaces().flatMap(\.sessionRPCObjects).map(RPCValue.object)))
        case .listPanes:
            return JSONRPCResponse(id: request.id, result: .array(controller.allWorkspaces().flatMap(\.paneRPCObjects).map(RPCValue.object)))
        case .terminalHistory:
            guard let historyRequest = ControlPlaneHistoryRequest(rpcValue: request.params) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "invalid history request"))
            }
            guard let history = controller.terminalHistory(historyRequest) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "pane not found"))
            }
            return JSONRPCResponse(id: request.id, result: history.rpcValue)
        case .clearTerminalHistory:
            guard let clearRequest = ControlPlaneHistoryClearRequest(rpcValue: request.params) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "invalid history clear request"))
            }
            guard let result = controller.clearTerminalHistory(clearRequest) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target not found"))
            }
            return JSONRPCResponse(id: request.id, result: result.rpcValue)
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
        case .configDoctor:
            return JSONRPCResponse(
                id: request.id,
                result: .array(configurationCoordinator.diagnostics().map(\.rpcValue))
            )
        case .configReload:
            let result = configurationCoordinator.reload()
            return JSONRPCResponse(
                id: request.id,
                result: .object([
                    "applied": .bool(result.applied),
                    "diagnostics": .array(result.diagnostics.map(\.rpcValue)),
                ])
            )
        case .terminalEvents:
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError(code: -32600, message: "terminal.events requires a streaming client")
            )
        case .none:
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32601, message: "method not found"))
        }
    }

    @MainActor
    private func navigationResponse(
        id: String?,
        workspace: Workspace?,
        unavailableMessage: String
    ) -> JSONRPCResponse {
        guard let workspace,
              let context = controller.resolveTerminalTarget(.focused)
        else {
            return JSONRPCResponse(id: id, error: JSONRPCError(code: 409, message: unavailableMessage))
        }

        return JSONRPCResponse(
            id: id,
            result: ControlPlaneActionResult(
                target: context,
                workspace: .object(workspace.rpcObject)
            ).rpcValue
        )
    }

    private func handleStream(descriptor: Int32, request: JSONRPCRequest) throws -> Bool {
        guard ControlMethod(rawValue: request.method) == .terminalEvents else {
            return false
        }

        let encoder = JSONEncoder()
        let subscription = terminalEventBroadcaster.subscribe()
        defer { terminalEventBroadcaster.unsubscribe(subscription.id) }

        let ack = JSONRPCResponse(id: request.id, result: .string("subscribed"))
        try UnixSocketIO.writeLine(try encoder.encode(ack), to: descriptor)

        while true {
            guard let event = subscription.subscription.nextEvent() else {
                continue
            }

            let notification = JSONRPCRequest(
                id: nil,
                method: ControlMethod.terminalEvents.rawValue,
                params: event.rpcValue
            )
            do {
                try UnixSocketIO.writeLine(try encoder.encode(notification), to: descriptor)
            } catch UnixSocketError.writeFailed {
                break
            }
        }

        return true
    }
}

private func mainActorSyncThrowing<T: Sendable>(_ body: @MainActor () throws -> T) throws -> T {
    if Thread.isMainThread {
        return try MainActor.assumeIsolated(body)
    }

    let result = DispatchQueue.main.sync {
        Result {
            try MainActor.assumeIsolated(body)
        }
    }
    return try result.get()
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

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}

private extension OmuxConfigDiagnostic {
    var rpcValue: RPCValue {
        .object([
            "severity": .string(severity.rawValue),
            "message": .string(message),
            "filePath": filePath.map(RPCValue.string) ?? .null,
            "line": line.map(RPCValue.integer) ?? .null,
        ])
    }
}

private extension Workspace {
    var rpcObject: [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "name": .string(name),
            "generatedName": .string(generatedName),
            "customName": customName.map { .string($0) } ?? .null,
            "rootPath": .string(rootPath),
            "tabCount": .integer(tabs.count),
            "paneCount": .integer(tabs.reduce(into: 0) { $0 += $1.panes.count }),
            "focusedTabID": .string(focusedTabID.rawValue),
            "focusedPaneID": focusedPane.map { .string($0.id.rawValue) } ?? .null,
            "focusedPaneStackID": focusedPaneStack.map { .string($0.id.rawValue) } ?? .null,
            "focusedSessionID": focusedPane.map { .string($0.session.id.rawValue) } ?? .null,
            "tabs": .array(tabs.map { .object($0.rpcObject(workspaceID: id)) }),
        ]
    }

    var sessionRPCObjects: [[String: RPCValue]] {
        tabs.flatMap { tab in
            tab.panes.map { pane in
                [
                    "workspaceID": .string(id.rawValue),
                    "tabID": .string(tab.id.rawValue),
                    "paneStackID": tab.rootLayout.paneStack(containingPaneID: pane.id).map { .string($0.id.rawValue) } ?? .null,
                    "paneID": .string(pane.id.rawValue),
                    "sessionID": .string(pane.session.id.rawValue),
                    "workingDirectory": .string(pane.session.workingDirectory),
                    "reportedWorkingDirectory": pane.terminalState.reportedWorkingDirectory.map(RPCValue.string) ?? .null,
                    "focused": .bool(focusedTabID == tab.id && tab.focusedPaneID == pane.id),
                ]
            }
        }
    }

    var paneRPCObjects: [[String: RPCValue]] {
        tabs.flatMap { tab in
            tab.panes.map { pane in
                [
                    "workspaceID": .string(id.rawValue),
                    "tabID": .string(tab.id.rawValue),
                    "paneStackID": tab.rootLayout.paneStack(containingPaneID: pane.id).map { .string($0.id.rawValue) } ?? .null,
                    "paneID": .string(pane.id.rawValue),
                    "sessionID": .string(pane.session.id.rawValue),
                    "title": .string(pane.title),
                    "focused": .bool(focusedTabID == tab.id && tab.focusedPaneID == pane.id),
                ]
            }
        }
    }
}

private extension WorkspaceSummary {
    var rpcObject: [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "name": .string(name),
            "generatedName": .string(generatedName),
            "customName": customName.map { .string($0) } ?? .null,
            "rootPath": .string(rootPath),
            "tabCount": .integer(tabCount),
            "paneCount": .integer(paneCount),
        ]
    }
}

private extension Tab {
    func rpcObject(workspaceID: WorkspaceID) -> [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "workspaceID": .string(workspaceID.rawValue),
            "title": .string(title),
            "focusedPaneID": .string(focusedPaneID.rawValue),
            "focusedPaneStackID": focusedPaneStack.map { .string($0.id.rawValue) } ?? .null,
            "paneStacks": .array(paneStacks.map { .object($0.rpcObject(workspaceID: workspaceID, tabID: id)) }),
            "panes": .array(panes.map { .object($0.rpcObject(workspaceID: workspaceID, tabID: id, paneStackID: rootLayout.paneStack(containingPaneID: $0.id)?.id, focused: focusedPaneID == $0.id)) }),
        ]
    }
}

private extension PaneStack {
    func rpcObject(workspaceID: WorkspaceID, tabID: TabID) -> [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "workspaceID": .string(workspaceID.rawValue),
            "tabID": .string(tabID.rawValue),
            "focusedPaneID": .string(focusedPaneID.rawValue),
            "paneIDs": .array(panes.map { .string($0.id.rawValue) }),
        ]
    }
}

private extension Pane {
    func rpcObject(workspaceID: WorkspaceID, tabID: TabID, paneStackID: PaneStackID?, focused: Bool) -> [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "workspaceID": .string(workspaceID.rawValue),
            "tabID": .string(tabID.rawValue),
            "paneStackID": paneStackID.map { .string($0.rawValue) } ?? .null,
            "sessionID": .string(session.id.rawValue),
            "title": .string(title),
            "workingDirectory": .string(session.workingDirectory),
            "reportedWorkingDirectory": terminalState.reportedWorkingDirectory.map(RPCValue.string) ?? .null,
            "focused": .bool(focused),
        ]
    }
}
