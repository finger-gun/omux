import Foundation
import OmuxControlPlane
import OmuxConfig
import OmuxCore
import OmuxVault

private enum VaultControlPlaneError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "Agent Sessions store unavailable"
    }
}

final class OpenMUXControlPlaneService: @unchecked Sendable {
    private final class VaultAwaitBox<T>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    private final class VaultWaiter: @unchecked Sendable {
        func wait<T>(
            store: VaultStore,
            operation: @escaping @Sendable (VaultStore) async throws -> T
        ) throws -> T {
            let semaphore = DispatchSemaphore(value: 0)
            let box = VaultAwaitBox<T>()
            Task.detached {
                do {
                    box.result = Result<T, Error>.success(try await operation(store))
                } catch {
                    box.result = Result<T, Error>.failure(error)
                }
                semaphore.signal()
            }
            semaphore.wait()
            return try box.result!.get()
        }
    }

    private struct EventQueue<Element> {
        private var storage: [Element] = []
        private var headIndex = 0

        var isEmpty: Bool {
            headIndex >= storage.count
        }

        mutating func append(_ value: Element) {
            storage.append(value)
        }

        mutating func popFirst() -> Element? {
            guard headIndex < storage.count else {
                storage.removeAll(keepingCapacity: true)
                headIndex = 0
                return nil
            }

            let value = storage[headIndex]
            headIndex += 1

            if headIndex > 64, headIndex * 2 >= storage.count {
                storage.removeFirst(headIndex)
                headIndex = 0
            }

            return value
        }
    }

    private final class TerminalEventSubscription {
        private let condition = NSCondition()
        private var queue = EventQueue<ControlPlaneTerminalEvent>()
        private var cancelled = false

        func push(_ event: ControlPlaneTerminalEvent) {
            condition.lock()
            defer { condition.unlock() }
            guard cancelled == false else {
                return
            }
            queue.append(event)
            condition.signal()
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

            return queue.popFirst()
        }

        func cancel() {
            condition.lock()
            cancelled = true
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
    private let extensionPaneActionService: ExtensionPaneActionService
    private let vaultStore: VaultStore?
    private let server: LocalControlServer
    private let terminalEventBroadcaster = TerminalEventBroadcaster()
    private let vaultWaiter = VaultWaiter()
    var agentSessionsUIHandler: (@MainActor @Sendable (String) -> RPCValue)?

    init(
        controller: WorkspaceController,
        configurationCoordinator: OpenMUXConfigurationCoordinator,
        extensionPaneActionService: ExtensionPaneActionService? = nil,
        vaultStore: VaultStore? = nil,
        socketPath: String = ControlPlaneSocket.defaultPath()
    ) {
        self.controller = controller
        self.configurationCoordinator = configurationCoordinator
        self.extensionPaneActionService = extensionPaneActionService ?? ExtensionPaneActionService(controller: controller)
        if let vaultStore {
            self.vaultStore = vaultStore
        } else {
            do {
                self.vaultStore = try VaultStore(
                    databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("omux-agent-sessions-control-\(UUID().uuidString).sqlite"),
                    configuration: VaultConfiguration(enabled: false)
                )
            } catch {
                fputs("error: failed to initialize disabled Agent Sessions control-plane store: \(error)\n", stderr)
                self.vaultStore = nil
            }
        }
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
                let created = workspace.focusedPane.flatMap { pane -> ControlPlaneTerminalContext? in
                    guard let session = pane.terminalSession else {
                        return nil
                    }
                    return ControlPlaneTerminalContext(
                        workspaceID: workspace.id,
                        tabID: workspace.focusedTabID,
                        paneStackID: workspace.focusedPaneStack?.id,
                        paneID: pane.id,
                        sessionID: session.id
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
            let params = request.params?.objectValue ?? [:]
            let workingDirectory = Self.nonEmptyString(params["workingDirectory"])
            let title = Self.nonEmptyString(params["title"])
            let paneStackID = Self.nonEmptyString(params["paneStackID"]).map(PaneStackID.init(rawValue:))
            if let workspace = try controller.createPaneTab(
                in: paneStackID,
                workingDirectory: workingDirectory,
                title: title
            ) {
                let created = workspace.focusedPane.flatMap { pane -> ControlPlaneTerminalContext? in
                    guard let session = pane.terminalSession else {
                        return nil
                    }
                    return ControlPlaneTerminalContext(
                        workspaceID: workspace.id,
                        tabID: workspace.focusedTabID,
                        paneStackID: workspace.focusedPaneStack?.id,
                        paneID: pane.id,
                        sessionID: session.id
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
        case .paneStatus:
            guard let paneStatusRequest = ControlPlanePaneStatusRequest(rpcValue: request.params) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "invalid pane status request"))
            }
            guard let result = controller.setPaneStatus(paneStatusRequest) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "target not found"))
            }
            return JSONRPCResponse(id: request.id, result: result.rpcValue)
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
        case .agentSessionsList:
            let searchRequest = VaultSearchRequest(rpcValue: request.params)
            let result = try awaitVault { store in
                try await store.search(searchRequest)
            }
            return JSONRPCResponse(id: request.id, result: result.rpcValue)
        case .agentSessionsSearch:
            let searchRequest = VaultSearchRequest(rpcValue: request.params)
            let result = try awaitVault { store in
                try await store.search(searchRequest)
            }
            return JSONRPCResponse(id: request.id, result: result.rpcValue)
        case .agentSessionsPreview:
            guard let sessionID = request.params?.objectValue?["sessionID"]?.stringValue ?? request.params?.objectValue?["id"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing sessionID"))
            }
            guard let preview = try awaitVault({ store in try await store.preview(sessionID: sessionID) }) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "agent session not found"))
            }
            return JSONRPCResponse(id: request.id, result: preview.rpcValue)
        case .agentSessionsResume:
            guard let params = request.params?.objectValue,
                  let sessionID = params["sessionID"]?.stringValue ?? params["id"]?.stringValue
            else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing sessionID"))
            }
            let destination = params["destination"]?.stringValue.flatMap(VaultResumeDestination.init(rawValue:)) ?? .focused
            guard let snapshot = try awaitVault({ store in try await store.resumeSnapshot(sessionID: sessionID) }),
                  let command = snapshot.resumeCommand,
                  command.isEmpty == false
            else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 409, message: "agent session cannot be resumed"))
            }
            guard let result = try resumeVault(command: command, workingDirectory: snapshot.workingDirectory, destination: destination) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "resume target unavailable"))
            }
            return JSONRPCResponse(id: request.id, result: result.rpcValue)
        case .agentSessionsReindex:
            let agent = request.params?.objectValue?["agent"]?.stringValue.flatMap(VaultAgentKind.init(rawValue:))
            let warnings = try awaitVault { store in
                try await store.reindex(agent: agent)
            }
            return JSONRPCResponse(id: request.id, result: .object(["ok": .bool(true), "warnings": .array(warnings.map(RPCValue.string))]))
        case .agentSessionsExport:
            guard case .array(let rawIDs)? = request.params?.objectValue?["ids"] else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing ids"))
            }
            let ids = rawIDs.compactMap(\.stringValue)
            let data = try awaitVault { store in
                try await store.export(ids: ids)
            }
            return JSONRPCResponse(id: request.id, result: .object(["data": .string(data.base64EncodedString())]))
        case .agentSessionsImport:
            guard let dataString = request.params?.objectValue?["data"]?.stringValue,
                  let data = Data(base64Encoded: dataString)
            else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing base64 data"))
            }
            try awaitVault { store in
                try await store.import(data: data)
            }
            return JSONRPCResponse(id: request.id, result: .object(["ok": .bool(true)]))
        case .agentSessionsAgents:
            let agents = try awaitVault { store in
                try await store.availableAgents()
            }
            return JSONRPCResponse(
                id: request.id,
                result: .array(agents.map { .string($0.rawValue) })
            )
        case .agentSessionsUI:
            let action = request.params?.objectValue?["action"]?.stringValue ?? "open"
            guard let agentSessionsUIHandler else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "agent sessions UI unavailable"))
            }
            let result = agentSessionsUIHandler(action)
            return JSONRPCResponse(id: request.id, result: result)
        case .createExtensionPane:
            guard let params = request.params?.objectValue,
                  let pluginID = params["pluginID"]?.stringValue,
                  pluginID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing pluginID"))
            }
            let descriptor = extensionPaneDescriptor(pluginID: pluginID, params: params)
            let axis = params["axis"]?.stringValue.flatMap(PaneSplitAxis.init(rawValue:)) ?? .columns
            let title = params["title"]?.stringValue ?? pluginID
            guard let result = controller.createExtensionPane(title: title, descriptor: descriptor, axis: axis) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "no active workspace"))
            }
            return JSONRPCResponse(id: request.id, result: .object(result.rpcObject))
        case .updateExtensionPane:
            guard let params = request.params?.objectValue,
                  let paneID = params["paneID"]?.stringValue.map(PaneID.init(rawValue:)),
                  let pluginID = params["pluginID"]?.stringValue,
                  pluginID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing paneID or pluginID"))
            }
            let descriptor = extensionPaneDescriptor(pluginID: pluginID, params: params)
            guard let result = controller.updateExtensionPane(
                paneID: paneID,
                descriptor: descriptor,
                title: params["title"]?.stringValue
            ) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "extension pane not found"))
            }
            return JSONRPCResponse(id: request.id, result: .object(result.rpcObject))
        case .extensionPaneAction:
            guard let actionRequest = extensionPaneActionRequest(params: request.params?.objectValue) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "invalid extension pane action"))
            }
            do {
                let response = try extensionPaneActionService.dispatch(actionRequest)
                return JSONRPCResponse(id: request.id, result: .object(response.rpcObject))
            } catch {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: String(describing: error)))
            }
        case .closeExtensionPane:
            guard let paneID = request.params?.objectValue?["paneID"]?.stringValue.map(PaneID.init(rawValue:)) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "missing paneID"))
            }
            guard let pane = controller.allWorkspaces().lazy.flatMap(\.panes).first(where: { $0.id == paneID }) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "extension pane not found"))
            }
            guard pane.extensionPane != nil else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "pane is not an extension pane"))
            }
            guard let result = try controller.closeExtensionPane(paneID: paneID) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 404, message: "extension pane not found"))
            }
            return JSONRPCResponse(id: request.id, result: .object(result.rpcObject))
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
        case .configGet:
            return JSONRPCResponse(id: request.id, result: try rpcValue(for: OmuxConfigExporter().export()))
        case .configApply:
            guard let jsonFile = request.params?.objectValue?["jsonFile"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: 400, message: "jsonFile is required"))
            }
            let result = try OmuxConfigEditor().apply(jsonFileURL: URL(fileURLWithPath: jsonFile))
            if result.diagnostics.contains(where: { $0.severity.isError }) {
                return JSONRPCResponse(id: request.id, result: try rpcValue(for: result))
            }
            let reloadResult = configurationCoordinator.reload()
            var value = try rpcValue(for: result).objectValue ?? [:]
            value["reload"] = .object([
                "applied": .bool(reloadResult.applied),
                "diagnostics": .array(reloadResult.diagnostics.map(\.rpcValue)),
            ])
            return JSONRPCResponse(id: request.id, result: .object(value))
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

    private func awaitVault<T>(_ operation: @escaping @Sendable (VaultStore) async throws -> T) throws -> T {
        guard let vaultStore else {
            throw VaultControlPlaneError.unavailable
        }
        return try vaultWaiter.wait(store: vaultStore, operation: operation)
    }

    @MainActor
    private func resumeVault(
        command: String,
        workingDirectory: String?,
        destination: VaultResumeDestination
    ) throws -> ControlPlaneActionResult? {
        switch destination {
        case .focused:
            return try controller.runCommand(target: .focused, command: command)
        case .newPaneTab:
            guard try controller.createPaneTab() != nil else {
                return nil
            }
            return try controller.runCommand(target: .focused, command: command)
        case .split:
            guard try controller.splitFocusedPane(axis: .columns) != nil else {
                return nil
            }
            return try controller.runCommand(target: .focused, command: command)
        case .workspace:
            guard let workingDirectory else {
                return try controller.runCommand(target: .focused, command: command)
            }
            let workspace = try controller.openWorkspace(at: workingDirectory)
            guard let context = controller.resolveTerminalTarget(.focused) else {
                return ControlPlaneActionResult(workspace: .object(workspace.rpcObject))
            }
            let runResult = try controller.runCommand(target: .focused, command: command)
            return runResult ?? ControlPlaneActionResult(target: context, workspace: .object(workspace.rpcObject))
        }
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

private func extensionPaneDescriptor(pluginID: String, params: [String: RPCValue]) -> ExtensionPaneDescriptor {
    let contentKind = params["contentKind"]?.stringValue.flatMap(ExtensionPaneContentKind.init(rawValue:)) ?? .html
    let status = params["status"]?.stringValue.flatMap(ExtensionPaneStatus.init(rawValue:)) ?? .ready
    let presentation = params["presentation"]?.stringValue.flatMap(ExtensionPanePresentationStyle.init(rawValue:)) ?? .paneTab
    return ExtensionPaneDescriptor(
        pluginID: pluginID,
        contentKind: contentKind,
        source: params["source"]?.stringValue,
        html: params["html"]?.stringValue,
        status: status,
        message: params["message"]?.stringValue,
        actionsEnabled: params["actionsEnabled"]?.boolValue == true,
        presentationStyle: presentation
    )
}

private func extensionPaneActionRequest(params: [String: RPCValue]?) -> ExtensionPaneActionRequest? {
    guard let params,
          let paneID = params["paneID"]?.stringValue.map(PaneID.init(rawValue:)),
          let pluginID = params["pluginID"]?.stringValue,
          let action = params["action"]?.stringValue
    else {
        return nil
    }
    return ExtensionPaneActionRequest(
        paneID: paneID,
        pluginID: pluginID,
        action: action,
        payload: params["payload"]?.omuxValue ?? .object([:])
    )
}

private extension ExtensionPaneActionResponse {
    var rpcObject: [String: RPCValue] {
        [
            "success": .bool(success),
            "message": message.map(RPCValue.string) ?? .null,
            "payload": RPCValue(payload),
        ]
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

private func rpcValue<T: Encodable>(for value: T) throws -> RPCValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(RPCValue.self, from: data)
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

private extension ExtensionPaneActionResult {
    var rpcObject: [String: RPCValue] {
        [
            "ok": .bool(true),
            "workspaceID": .string(workspace.id.rawValue),
            "tabID": tabID.map { .string($0.rawValue) } ?? .null,
            "paneStackID": paneStackID.map { .string($0.rawValue) } ?? .null,
            "floatingPaneModalID": floatingPaneModalID.map { .string($0.rawValue) } ?? .null,
            "paneID": .string(pane.id.rawValue),
            "title": .string(pane.title),
            "pluginID": pane.extensionPane.map { .string($0.pluginID) } ?? .null,
            "contentKind": pane.extensionPane.map { .string($0.contentKind.rawValue) } ?? .null,
            "presentation": pane.extensionPane.map { .string($0.presentationStyle.rawValue) } ?? .null,
            "source": pane.extensionPane?.source.map(RPCValue.string) ?? .null,
            "workspace": .object(workspace.rpcObject),
        ]
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
            "paneCount": .integer(panes.count),
            "focusedTabID": .string(focusedTabID.rawValue),
            "focusedFloatingPaneModalID": focusedFloatingPaneModalID.map { .string($0.rawValue) } ?? .null,
            "focusedPaneID": focusedPane.map { .string($0.id.rawValue) } ?? .null,
            "focusedPaneStackID": focusedPaneStack.map { .string($0.id.rawValue) } ?? .null,
            "focusedSessionID": focusedPane?.terminalSession.map { .string($0.id.rawValue) } ?? .null,
            "tabs": .array(tabs.map { .object($0.rpcObject(workspaceID: id)) }),
            "floatingPaneModals": .array(floatingPaneModals.map { .object($0.rpcObject(workspaceID: id)) }),
        ]
    }

    var sessionRPCObjects: [[String: RPCValue]] {
        tabs.flatMap { tab in
            tab.panes.compactMap { pane in
                guard let session = pane.terminalSession else {
                    return nil
                }
                return [
                    "workspaceID": .string(id.rawValue),
                    "tabID": .string(tab.id.rawValue),
                    "paneStackID": tab.rootLayout.paneStack(containingPaneID: pane.id).map { .string($0.id.rawValue) } ?? .null,
                    "floatingPaneModalID": .null,
                    "paneID": .string(pane.id.rawValue),
                    "sessionID": .string(session.id.rawValue),
                    "workingDirectory": .string(session.workingDirectory),
                    "reportedWorkingDirectory": pane.terminalState.reportedWorkingDirectory.map(RPCValue.string) ?? .null,
                    "progress": pane.terminalState.progress.rpcValue,
                    "focused": .bool(focusedFloatingPaneModalID == nil && focusedTabID == tab.id && tab.focusedPaneID == pane.id),
                ]
            }
        } + floatingPaneModals.flatMap { modal in
            modal.paneStack.panes.compactMap { pane in
                guard let session = pane.terminalSession else {
                    return nil
                }
                return [
                    "workspaceID": .string(id.rawValue),
                    "tabID": .null,
                    "paneStackID": .string(modal.paneStack.id.rawValue),
                    "floatingPaneModalID": .string(modal.id.rawValue),
                    "paneID": .string(pane.id.rawValue),
                    "sessionID": .string(session.id.rawValue),
                    "workingDirectory": .string(session.workingDirectory),
                    "reportedWorkingDirectory": pane.terminalState.reportedWorkingDirectory.map(RPCValue.string) ?? .null,
                    "progress": pane.terminalState.progress.rpcValue,
                    "focused": .bool(focusedFloatingPaneModalID == modal.id && modal.paneStack.focusedPaneID == pane.id),
                ]
            }
        }
    }

    var paneRPCObjects: [[String: RPCValue]] {
        let dockedPanes: [[String: RPCValue]] = tabs.flatMap { tab in
            tab.panes.map { pane in
                [
                    "workspaceID": .string(id.rawValue),
                    "tabID": .string(tab.id.rawValue),
                    "paneStackID": tab.rootLayout.paneStack(containingPaneID: pane.id).map { .string($0.id.rawValue) } ?? .null,
                    "floatingPaneModalID": .null,
                    "paneID": .string(pane.id.rawValue),
                    "contentKind": .string(pane.isTerminal ? "terminal" : "extension"),
                    "sessionID": pane.terminalSession.map { .string($0.id.rawValue) } ?? .null,
                    "pluginID": pane.extensionPane.map { .string($0.pluginID) } ?? .null,
                    "presentation": pane.extensionPane.map { .string($0.presentationStyle.rawValue) } ?? .null,
                    "title": .string(pane.title),
                    "progress": pane.terminalState.progress.rpcValue,
                    "focused": .bool(focusedFloatingPaneModalID == nil && focusedTabID == tab.id && tab.focusedPaneID == pane.id),
                ]
            }
        }
        let floatingPanes: [[String: RPCValue]] = floatingPaneModals.flatMap { modal in
            modal.panes.map { pane in
                [
                    "workspaceID": .string(id.rawValue),
                    "tabID": .null,
                    "paneStackID": .string(modal.paneStack.id.rawValue),
                    "floatingPaneModalID": .string(modal.id.rawValue),
                    "paneID": .string(pane.id.rawValue),
                    "contentKind": .string(pane.isTerminal ? "terminal" : "extension"),
                    "sessionID": pane.terminalSession.map { .string($0.id.rawValue) } ?? .null,
                    "pluginID": pane.extensionPane.map { .string($0.pluginID) } ?? .null,
                    "presentation": pane.extensionPane.map { .string($0.presentationStyle.rawValue) } ?? .null,
                    "title": .string(pane.title),
                    "progress": pane.terminalState.progress.rpcValue,
                    "focused": .bool(focusedFloatingPaneModalID == modal.id && modal.paneStack.focusedPaneID == pane.id),
                ]
            }
        }
        return dockedPanes + floatingPanes
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

private extension FloatingPaneModal {
    func rpcObject(workspaceID: WorkspaceID) -> [String: RPCValue] {
        [
            "id": .string(id.rawValue),
            "workspaceID": .string(workspaceID.rawValue),
            "paneStackID": .string(paneStack.id.rawValue),
            "focusedPaneID": .string(paneStack.focusedPaneID.rawValue),
            "frame": .object(frame.rpcObject),
            "paneIDs": .array(paneStack.panes.map { .string($0.id.rawValue) }),
        ]
    }
}

private extension FloatingPaneModalFrame {
    var rpcObject: [String: RPCValue] {
        [
            "originX": .number(x),
            "originY": .number(y),
            "width": .number(width),
            "height": .number(height),
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
            "contentKind": .string(isTerminal ? "terminal" : "extension"),
            "sessionID": terminalSession.map { .string($0.id.rawValue) } ?? .null,
            "pluginID": extensionPane.map { .string($0.pluginID) } ?? .null,
            "presentation": extensionPane.map { .string($0.presentationStyle.rawValue) } ?? .null,
            "title": .string(title),
            "workingDirectory": terminalSession.map { .string($0.workingDirectory) } ?? .null,
            "reportedWorkingDirectory": terminalState.reportedWorkingDirectory.map(RPCValue.string) ?? .null,
            "progress": terminalState.progress.rpcValue,
            "focused": .bool(focused),
        ]
    }
}

private extension OpenMUXControlPlaneService {
    static func nonEmptyString(_ value: RPCValue?) -> String? {
        guard let string = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              string.isEmpty == false
        else {
            return nil
        }
        return string
    }
}

private extension Optional where Wrapped == PaneProgress {
    var rpcValue: RPCValue {
        guard let progress = self else {
            return .null
        }
        return .object([
            "state": .string(progress.state.rawValue),
            "value": progress.value.map(RPCValue.integer) ?? .null,
        ])
    }
}
