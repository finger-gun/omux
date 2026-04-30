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
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let session = SessionDescriptor(shell: shell, workingDirectory: path)
        let pane = Pane(title: directoryURL.lastPathComponent.isEmpty ? "workspace" : directoryURL.lastPathComponent, session: session)
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(
            name: directoryURL.lastPathComponent.isEmpty ? "OpenMUX" : directoryURL.lastPathComponent,
            rootPath: path,
            tabs: [tab],
            focusedTabID: tab.id
        )

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(session: session, to: pane)

        lock.lock()
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        lock.unlock()

        try hookRunner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-opened",
                workspaceID: workspace.id,
                sessionID: session.id,
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
}
