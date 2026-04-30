import AppKit
import Foundation
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge

public final class WorkspaceController: @unchecked Sendable {
    private let lock = NSLock()
    private let bridge: GhosttyTerminalBridge
    private let hookRunner: ExternalHookRunner
    private var workspaces: [Workspace] = []
    private var activeWorkspaceID: WorkspaceID?
    private var lastNotification: NotificationRequest?

    public var onChange: ((Workspace) -> Void)?

    public init(
        bridge: GhosttyTerminalBridge,
        hookRunner: ExternalHookRunner
    ) {
        self.bridge = bridge
        self.hookRunner = hookRunner
    }

    public func openWorkspace(at path: String) throws -> Workspace {
        let directoryURL = URL(fileURLWithPath: path)
        let pane = makePane(title: directoryURL.lastPathComponent.isEmpty ? "workspace" : directoryURL.lastPathComponent, workingDirectory: path)
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(
            name: directoryURL.lastPathComponent.isEmpty ? "OpenMUX" : directoryURL.lastPathComponent,
            rootPath: path,
            tabs: [tab],
            focusedTabID: tab.id
        )

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(session: pane.session, to: pane)

        lock.lock()
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        lock.unlock()

        try hookRunner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-opened",
                workspaceID: workspace.id,
                sessionID: pane.session.id,
                metadata: ["path": path]
            )
        )

        onChange?(workspace)
        return workspace
    }

    public func listWorkspaces() -> [WorkspaceSummary] {
        lock.lock()
        defer { lock.unlock() }
        return workspaces.map(WorkspaceSummary.init(workspace:))
    }

    @discardableResult
    public func focus(sessionID: SessionID) throws -> Bool {
        var updatedWorkspace: Workspace?
        lock.lock()
        for index in workspaces.indices {
            if workspaces[index].focus(sessionID: sessionID) {
                activeWorkspaceID = workspaces[index].id
                updatedWorkspace = workspaces[index]
                break
            }
        }
        lock.unlock()

        guard let updatedWorkspace else {
            return false
        }

        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-focused",
                workspaceID: updatedWorkspace.id,
                sessionID: sessionID
            )
        )

        onChange?(updatedWorkspace)
        return true
    }

    public func restore(workspaceID: WorkspaceID) -> Workspace? {
        lock.lock()
        defer { lock.unlock() }

        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return nil
        }

        activeWorkspaceID = workspace.id
        onChange?(workspace)
        return workspace
    }

    public func notify(_ request: NotificationRequest) throws {
        lock.lock()
        lastNotification = request
        lock.unlock()

        DispatchQueue.main.async {
            NSApplication.shared.requestUserAttention(.informationalRequest)
        }

        try hookRunner.emit(
            HookInvocation(
                category: .ui,
                name: "notification-raised",
                workspaceID: activeWorkspaceID,
                metadata: [
                    "title": request.title,
                    "severity": request.severity.rawValue,
                ]
            )
        )
    }

    public func activeWorkspace() -> Workspace? {
        lock.lock()
        defer { lock.unlock() }
        guard let activeWorkspaceID else {
            return nil
        }

        return workspaces.first(where: { $0.id == activeWorkspaceID })
    }

    public func latestNotification() -> NotificationRequest? {
        lock.lock()
        defer { lock.unlock() }
        return lastNotification
    }

    public var terminalBridge: GhosttyTerminalBridge {
        bridge
    }

    @discardableResult
    public func createTab() throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let workingDirectory = workspaces[index].rootPath
        let pane = makePane(title: "Shell", workingDirectory: workingDirectory)
        let tab = Tab(title: "Tab \(workspaces[index].tabs.count + 1)", panes: [pane], focusedPaneID: pane.id)
        workspaces[index].appendTab(tab)
        let updatedWorkspace = workspaces[index]
        lock.unlock()

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(session: pane.session, to: pane)

        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "tab-created",
                workspaceID: updatedWorkspace.id,
                tabID: tab.id,
                paneID: pane.id,
                sessionID: pane.session.id
            )
        )

        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func splitFocusedPane(axis: PaneSplitAxis = .columns) throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex,
              let focusedPane = workspaces[index].focusedPane
        else {
            lock.unlock()
            return nil
        }

        let pane = makePane(title: focusedPane.title, workingDirectory: focusedPane.session.workingDirectory)
        let success = workspaces[index].appendPaneToFocusedTab(pane, axis: axis)
        let updatedWorkspace = success ? workspaces[index] : nil
        lock.unlock()

        guard let updatedWorkspace else {
            return nil
        }

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(session: pane.session, to: pane)

        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-created",
                workspaceID: updatedWorkspace.id,
                paneID: pane.id,
                sessionID: pane.session.id
            )
        )

        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func createPaneTab() throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex,
              let focusedPane = workspaces[index].focusedPane,
              let focusedStack = workspaces[index].focusedPaneStack
        else {
            lock.unlock()
            return nil
        }

        let pane = makePane(title: focusedPane.title, workingDirectory: focusedPane.session.workingDirectory)
        let success = workspaces[index].createPaneInFocusedStack(pane)
        let updatedWorkspace = success ? workspaces[index] : nil
        lock.unlock()

        guard let updatedWorkspace else {
            return nil
        }

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(session: pane.session, to: pane)

        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-tab-created",
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: pane.id,
                sessionID: pane.session.id,
                metadata: ["paneStackID": focusedStack.id.rawValue]
            )
        )

        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func closePaneTab(paneID: PaneID? = nil) throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let targetPaneID = paneID ?? workspaces[index].focusedPane?.id
        let targetStackID = targetPaneID.flatMap { paneStackID(for: $0, in: workspaces[index]) }
        let removedPane = targetPaneID.flatMap { workspaces[index].closePane($0) }
        let updatedWorkspace = removedPane == nil ? nil : workspaces[index]
        lock.unlock()

        guard let removedPane,
              let updatedWorkspace
        else {
            return nil
        }

        try bridge.teardown(paneID: removedPane.id)
        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-tab-closed",
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: removedPane.id,
                sessionID: removedPane.session.id,
                metadata: ["paneStackID": targetStackID?.rawValue ?? ""]
            )
        )

        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func focus(tabID: TabID) -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let index = activeWorkspaceIndex,
           workspaces[index].focusedTabID != tabID,
           workspaces[index].focus(tabID: tabID) {
            updatedWorkspace = workspaces[index]
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func focus(paneID: PaneID) -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let index = activeWorkspaceIndex,
           workspaces[index].focusedPane?.id != paneID,
           workspaces[index].focus(paneID: paneID) {
            updatedWorkspace = workspaces[index]
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func focusPaneTab(paneID: PaneID) -> Workspace? {
        focus(paneID: paneID)
    }

    @discardableResult
    public func runCommand(in sessionID: SessionID, command: String) throws -> Bool {
        guard let pane = pane(for: sessionID) else {
            return false
        }

        try hookRunner.emit(
            HookInvocation(
                category: .command,
                name: "command-started",
                workspaceID: activeWorkspaceID,
                paneID: pane.id,
                sessionID: sessionID,
                metadata: ["command": command]
            )
        )

        try bridge.run(command: command, inPane: pane.id)
        return true
    }

    public func handleInput(_ event: NormalizedKeyEvent, in paneID: PaneID) throws {
        try bridge.handle(event, inPane: paneID)
    }

    public func paste(_ text: String, in paneID: PaneID) throws {
        try bridge.send(text: text, toPane: paneID)
    }

    public func resize(paneID: PaneID, columns: Int, rows: Int) throws {
        try bridge.resize(paneID: paneID, columns: columns, rows: rows)
    }

    public func focusedPaneID(in workspace: Workspace) -> PaneID? {
        workspace.focusedPane?.id
    }

    private var activeWorkspaceIndex: Int? {
        guard let activeWorkspaceID else {
            return nil
        }

        return workspaces.firstIndex(where: { $0.id == activeWorkspaceID })
    }

    private func pane(for sessionID: SessionID) -> Pane? {
        lock.lock()
        defer { lock.unlock() }
        return workspaces
            .flatMap(\.tabs)
            .flatMap(\.panes)
            .first(where: { $0.session.id == sessionID })
    }

    private func paneStackID(for paneID: PaneID, in workspace: Workspace) -> PaneStackID? {
        workspace.tabs
            .compactMap { $0.rootLayout.paneStack(containingPaneID: paneID)?.id }
            .first
    }

    private func makePane(title: String, workingDirectory: String) -> Pane {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let session = SessionDescriptor(shell: shell, workingDirectory: workingDirectory)
        return Pane(title: title, session: session)
    }
}
