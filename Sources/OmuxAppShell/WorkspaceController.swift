import AppKit
import Foundation
import OmuxControlPlane
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge

public final class WorkspaceController: @unchecked Sendable {
    private let lock = NSLock()
    private let bridge: GhosttyTerminalBridge
    private let hookRunner: ExternalHookRunner
    private var workspaces: [Workspace] = []
    private var activeWorkspaceID: WorkspaceID?
    private var previousWorkspaceID: WorkspaceID?
    private var lastNotification: NotificationRequest?
    private lazy var terminalActionCoordinator = TerminalActionCoordinator(
        bridge: bridge,
        controller: self,
        hookRunner: hookRunner
    )

    public var onChange: ((Workspace) -> Void)?
    public var onTerminalEvent: ((ControlPlaneTerminalEvent) -> Void)?

    public init(
        bridge: GhosttyTerminalBridge,
        hookRunner: ExternalHookRunner
    ) {
        self.bridge = bridge
        self.hookRunner = hookRunner
        _ = terminalActionCoordinator
    }

    public func openWorkspace(at path: String) throws -> Workspace {
        let paneTitle = Self.basePaneTitle(for: path)
        let pane = makePane(title: paneTitle, workingDirectory: path)
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)

        lock.lock()
        let generatedWorkspaceName = nextGeneratedWorkspaceName()
        lock.unlock()

        let workspace = Workspace(
            generatedName: generatedWorkspaceName,
            rootPath: path,
            tabs: [tab],
            focusedTabID: tab.id
        )

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(session: pane.session, to: pane)

        lock.lock()
        workspaces.append(workspace)
        setActiveWorkspaceID(workspace.id)
        lock.unlock()

        try hookRunner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-opened",
                workspaceID: workspace.id,
                sessionID: pane.session.id,
                payload: .object(["path": .string(path)])
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

    public func allWorkspaces() -> [Workspace] {
        lock.lock()
        defer { lock.unlock() }
        return workspaces
    }

    func persistenceSnapshot() -> WorkspacePersistenceSnapshot? {
        lock.lock()
        let storedWorkspaces = workspaces.map(Self.sanitizedWorkspaceForPersistence)
        let storedActiveWorkspaceID = activeWorkspaceID
        lock.unlock()

        guard storedWorkspaces.isEmpty == false else {
            return nil
        }

        return WorkspacePersistenceSnapshot(
            workspaces: storedWorkspaces,
            activeWorkspaceID: storedActiveWorkspaceID
        )
    }

    @discardableResult
    func restorePersistedState(_ snapshot: WorkspacePersistenceSnapshot) throws -> Workspace? {
        let restoredWorkspaces = snapshot.workspaces.compactMap(Self.normalizedRestoredWorkspace)
        guard restoredWorkspaces.isEmpty == false else {
            return nil
        }

        let existingPaneIDs = allWorkspaces().flatMap { $0.tabs.flatMap(\.panes) }.map(\.id)
        for paneID in existingPaneIDs {
            try? bridge.teardown(paneID: paneID)
        }

        for workspace in restoredWorkspaces {
            for pane in workspace.tabs.flatMap(\.panes) {
                _ = try bridge.createSurface(for: pane)
                _ = try bridge.attach(session: pane.session, to: pane)
            }
        }

        let restoredActiveWorkspaceID = snapshot.activeWorkspaceID.flatMap { activeID in
            restoredWorkspaces.contains(where: { $0.id == activeID }) ? activeID : nil
        } ?? restoredWorkspaces.first?.id

        lock.lock()
        workspaces = restoredWorkspaces
        previousWorkspaceID = nil
        if let restoredActiveWorkspaceID {
            setActiveWorkspaceID(restoredActiveWorkspaceID, recordPrevious: false)
        }
        let updatedWorkspace = restoredActiveWorkspaceID.flatMap { activeID in
            workspaces.first(where: { $0.id == activeID })
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func focus(sessionID: SessionID) throws -> Bool {
        var updatedWorkspace: Workspace?
        lock.lock()
        for index in workspaces.indices {
            if workspaces[index].focus(sessionID: sessionID) {
                setActiveWorkspaceID(workspaces[index].id)
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

        setActiveWorkspaceID(workspace.id)
        onChange?(workspace)
        return workspace
    }

    public func notify(_ request: NotificationRequest) throws {
        deliverNotification(request)

        try hookRunner.emit(
            HookInvocation(
                category: .ui,
                name: "notification-raised",
                workspaceID: activeWorkspaceID,
                payload: .object([
                    "title": .string(request.title),
                    "body": .string(request.body),
                    "severity": .string(request.severity.rawValue),
                ])
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

    public func canDeleteActiveWorkspace() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return workspaces.count > 1 && activeWorkspaceIndex != nil
    }

    public func canRenameActiveWorkspace() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeWorkspaceIndex != nil
    }

    public func canRemoveActivePane() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = activeWorkspaceIndex,
              let focusedTab = workspaces[index].focusedTab
        else {
            return false
        }

        return workspaces[index].tabs.count > 1 || focusedTab.panes.count > 1
    }

    public var terminalBridge: GhosttyTerminalBridge {
        bridge
    }

    @discardableResult
    public func createWorkspace() throws -> Workspace {
        let rootPath = activeWorkspace()?.rootPath ?? FileManager.default.currentDirectoryPath
        return try openWorkspace(at: rootPath)
    }

    @discardableResult
    public func renameWorkspace(_ workspaceID: WorkspaceID, to proposedName: String) throws -> Workspace? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return nil
        }

        lock.lock()
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            lock.unlock()
            return nil
        }

        let uniqueName = uniqueWorkspaceDisplayName(baseName: trimmedName, excluding: workspaceID)
        workspaces[index].customName = uniqueName
        let updatedWorkspace = workspaces[index]
        lock.unlock()

        try hookRunner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-renamed",
                workspaceID: updatedWorkspace.id,
                payload: .object(["name": .string(updatedWorkspace.name)])
            )
        )

        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func removeCustomWorkspaceName(_ workspaceID: WorkspaceID) -> Workspace? {
        lock.lock()
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }),
              workspaces[index].customName != nil
        else {
            lock.unlock()
            return nil
        }

        workspaces[index].customName = nil
        let updatedWorkspace = workspaces[index]
        lock.unlock()

        onChange?(updatedWorkspace)
        return updatedWorkspace
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
                payload: .object(["paneStackID": .string(focusedStack.id.rawValue)])
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
                payload: .object([
                    "paneStackID": targetStackID.map { .string($0.rawValue) } ?? .null,
                ])
            )
        )

        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func deleteActiveWorkspace() throws -> Workspace? {
        guard let activeWorkspaceID else {
            return nil
        }
        return try closeWorkspace(activeWorkspaceID)
    }

    @discardableResult
    public func closeWorkspace(_ workspaceID: WorkspaceID) throws -> Workspace? {
        try removeWorkspaces(
            matching: { $0.id == workspaceID },
            preferredActiveWorkspaceID: nil
        )
    }

    @discardableResult
    public func closeOtherWorkspaces(keeping workspaceID: WorkspaceID) throws -> Workspace? {
        try removeWorkspaces(
            matching: { $0.id != workspaceID },
            preferredActiveWorkspaceID: workspaceID
        )
    }

    @discardableResult
    public func closeWorkspacesAbove(_ workspaceID: WorkspaceID) throws -> Workspace? {
        try closeWorkspaces(relativeTo: workspaceID) { targetIndex, _ in
            0..<targetIndex
        }
    }

    @discardableResult
    public func closeWorkspacesBelow(_ workspaceID: WorkspaceID) throws -> Workspace? {
        try closeWorkspaces(relativeTo: workspaceID) { targetIndex, totalCount in
            (targetIndex + 1)..<totalCount
        }
    }

    @discardableResult
    public func removeActivePane() throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex,
              let focusedPane = workspaces[index].focusedPane,
              let focusedTab = workspaces[index].focusedTab
        else {
            lock.unlock()
            return nil
        }

        let removedPane: Pane
        if focusedTab.panes.count == 1 {
            guard workspaces[index].tabs.count > 1,
                  let removedTab = workspaces[index].closeTab(focusedTab.id),
                  let tabPane = removedTab.panes.first
            else {
                lock.unlock()
                return nil
            }
            removedPane = tabPane
        } else {
            guard let pane = workspaces[index].tabs.firstIndex(where: { $0.id == focusedTab.id }).flatMap({ tabIndex in
                workspaces[index].tabs[tabIndex].removePane(focusedPane.id)
            }) else {
                lock.unlock()
                return nil
            }
            removedPane = pane
        }

        let updatedWorkspace = workspaces[index]
        lock.unlock()

        try bridge.teardown(paneID: removedPane.id)
        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-removed",
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: removedPane.id,
                sessionID: removedPane.session.id
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
    public func renamePaneTab(_ paneID: PaneID, to proposedName: String) -> Workspace? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return nil
        }

        lock.lock()
        var updatedWorkspace: Workspace?
        for workspaceIndex in workspaces.indices {
            if workspaces[workspaceIndex].updatePane(paneID, transform: { $0.title = trimmedName }) {
                updatedWorkspace = workspaces[workspaceIndex]
                break
            }
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }
        return updatedWorkspace
    }

    @discardableResult
    public func closeOtherPaneTabs(paneID: PaneID) throws -> Workspace? {
        try closePaneTabs(relativeTo: paneID) { panes, targetIndex in
            panes.enumerated().compactMap { index, pane in
                index == targetIndex ? nil : pane.id
            }
        }
    }

    @discardableResult
    public func closePaneTabsAbove(paneID: PaneID) throws -> Workspace? {
        try closePaneTabs(relativeTo: paneID) { panes, targetIndex in
            panes.prefix(targetIndex).map(\.id)
        }
    }

    @discardableResult
    public func closePaneTabsBelow(paneID: PaneID) throws -> Workspace? {
        try closePaneTabs(relativeTo: paneID) { panes, targetIndex in
            panes.suffix(from: targetIndex + 1).map(\.id)
        }
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
                payload: .object(["command": .string(command)])
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

    @discardableResult
    public func focusWorkspace(atDisplayIndex index: Int) -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if workspaces.indices.contains(index) {
            let workspace = workspaces[index]
            if activeWorkspaceID != workspace.id {
                setActiveWorkspaceID(workspace.id)
                updatedWorkspace = workspace
            }
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func focusPreviousWorkspace() -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let previousWorkspaceID,
           activeWorkspaceID != previousWorkspaceID,
           let index = workspaces.firstIndex(where: { $0.id == previousWorkspaceID }) {
            let workspace = workspaces[index]
            setActiveWorkspaceID(workspace.id)
            updatedWorkspace = workspace
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    public func canFocusPreviousWorkspace() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let previousWorkspaceID else {
            return false
        }

        return previousWorkspaceID != activeWorkspaceID && workspaces.contains(where: { $0.id == previousWorkspaceID })
    }

    private var activeWorkspaceIndex: Int? {
        guard let activeWorkspaceID else {
            return nil
        }

        return workspaces.firstIndex(where: { $0.id == activeWorkspaceID })
    }

    private func setActiveWorkspaceID(_ workspaceID: WorkspaceID, recordPrevious: Bool = true) {
        if recordPrevious, let activeWorkspaceID, activeWorkspaceID != workspaceID {
            previousWorkspaceID = activeWorkspaceID
        }
        activeWorkspaceID = workspaceID
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

    func terminalActionCoordinatorHandle(_ event: TerminalActionEvent) {
        terminalActionCoordinator.handle(event)
    }

    func publishTerminalEvent(_ event: ControlPlaneTerminalEvent) {
        onTerminalEvent?(event)
    }

    func deliverNotification(_ request: NotificationRequest) {
        lock.lock()
        lastNotification = request
        lock.unlock()

        DispatchQueue.main.async {
            NSApplication.shared.requestUserAttention(.informationalRequest)
        }
    }

    func applyTerminalActionState(_ event: TerminalActionEvent) -> WorkspaceTerminalActionContext? {
        var updatedWorkspace: Workspace?
        var context: WorkspaceTerminalActionContext?

        lock.lock()
        for workspaceIndex in workspaces.indices {
            for tabIndex in workspaces[workspaceIndex].tabs.indices {
                guard workspaces[workspaceIndex].tabs[tabIndex].panes.contains(where: { $0.id == event.paneID }) else {
                    continue
                }

                let workspaceID = workspaces[workspaceIndex].id
                let tabID = workspaces[workspaceIndex].tabs[tabIndex].id
                context = WorkspaceTerminalActionContext(
                    workspaceID: workspaceID,
                    tabID: tabID,
                    paneID: event.paneID,
                    sessionID: event.sessionID
                )

                switch event.action {
                case .workingDirectoryChanged(let path):
                    _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                        pane.session.workingDirectory = path
                        pane.terminalState.reportedWorkingDirectory = path
                    }
                    updatedWorkspace = workspaces[workspaceIndex]
                case .titleChanged(let title):
                    _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                        pane.title = title
                    }
                    updatedWorkspace = workspaces[workspaceIndex]
                case .tabTitleChanged(let title):
                    workspaces[workspaceIndex].tabs[tabIndex].title = title
                    updatedWorkspace = workspaces[workspaceIndex]
                case .progressReported(let state, let progress):
                    _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                        switch state {
                        case .removed:
                            pane.terminalState.progress = nil
                        case .active:
                            pane.terminalState.progress = PaneProgress(state: .active, value: progress)
                        case .error:
                            pane.terminalState.progress = PaneProgress(state: .error, value: progress)
                        case .indeterminate:
                            pane.terminalState.progress = PaneProgress(state: .indeterminate, value: progress)
                        case .paused:
                            pane.terminalState.progress = PaneProgress(state: .paused, value: progress)
                        }
                    }
                    updatedWorkspace = workspaces[workspaceIndex]
                case .childExited(let exitCode, let elapsedMilliseconds):
                    _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                        pane.terminalState.lastExit = PaneExitStatus(
                            exitCode: exitCode,
                            elapsedMilliseconds: elapsedMilliseconds
                        )
                    }
                    updatedWorkspace = workspaces[workspaceIndex]
                case .rendererHealthChanged(let isHealthy):
                    _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                        pane.terminalState.rendererHealthy = isHealthy
                    }
                    updatedWorkspace = workspaces[workspaceIndex]
                case .openURL, .desktopNotification, .bell, .commandFinished:
                    break
                }

                lock.unlock()
                if let updatedWorkspace {
                    onChange?(updatedWorkspace)
                }
                return context
            }
        }
        lock.unlock()
        return nil
    }

    private func uniqueWorkspaceDisplayName(baseName: String, excluding workspaceID: WorkspaceID? = nil) -> String {
        let existingNames = Set(
            workspaces
                .filter { $0.id != workspaceID }
                .map(\.name.localizedLowercase)
        )
        guard existingNames.contains(baseName.localizedLowercase) else {
            return baseName
        }

        var suffix = 2
        while true {
            let candidate = "\(baseName) \(suffix)"
            if existingNames.contains(candidate.localizedLowercase) == false {
                return candidate
            }
            suffix += 1
        }
    }

    private func nextGeneratedWorkspaceName() -> String {
        var suffix = 1
        while true {
            let candidate = "Workspace \(suffix)"
            if workspaces.contains(where: { $0.generatedName.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) == false {
                return candidate
            }
            suffix += 1
        }
    }

    private func makePane(title: String, workingDirectory: String) -> Pane {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let session = SessionDescriptor(shell: shell, workingDirectory: workingDirectory)
        return Pane(title: title, session: session)
    }

    private static func sanitizedWorkspaceForPersistence(_ workspace: Workspace) -> Workspace {
        Workspace(
            id: workspace.id,
            generatedName: workspace.generatedName,
            customName: workspace.customName,
            rootPath: workspace.rootPath,
            tabs: workspace.tabs.map(sanitizedTabForPersistence),
            focusedTabID: workspace.focusedTabID
        )
    }

    private static func sanitizedTabForPersistence(_ tab: Tab) -> Tab {
        Tab(
            id: tab.id,
            title: tab.title,
            rootLayout: sanitizedLayoutNodeForPersistence(tab.rootLayout),
            focusedPaneID: tab.focusedPaneID
        )
    }

    private static func sanitizedLayoutNodeForPersistence(_ node: TabLayoutNode) -> TabLayoutNode {
        switch node {
        case .paneStack(let paneStack):
            let panes = paneStack.panes.map(sanitizedPaneForPersistence)
            return .paneStack(
                PaneStack(
                    id: paneStack.id,
                    panes: panes,
                    focusedPaneID: paneStack.focusedPaneID
                )
            )
        case .split(let axis, let children):
            return .split(
                axis: axis,
                children: children.map(sanitizedLayoutNodeForPersistence)
            )
        }
    }

    private static func sanitizedPaneForPersistence(_ pane: Pane) -> Pane {
        Pane(
            id: pane.id,
            title: pane.title,
            session: pane.session,
            terminalState: PaneTerminalState()
        )
    }

    private static func normalizedRestoredWorkspace(_ workspace: Workspace) -> Workspace? {
        let normalizedTabs = workspace.tabs.compactMap(normalizedRestoredTab)
        guard normalizedTabs.isEmpty == false else {
            return nil
        }

        let focusedTabID = normalizedTabs.contains(where: { $0.id == workspace.focusedTabID })
            ? workspace.focusedTabID
            : normalizedTabs[0].id

        return Workspace(
            id: workspace.id,
            generatedName: workspace.generatedName,
            customName: workspace.customName,
            rootPath: workspace.rootPath,
            tabs: normalizedTabs,
            focusedTabID: focusedTabID
        )
    }

    private static func normalizedRestoredTab(_ tab: Tab) -> Tab? {
        let normalizedLayout = normalizedRestoredLayoutNode(tab.rootLayout)
        let panes = normalizedLayout.panes
        guard panes.isEmpty == false else {
            return nil
        }

        let focusedPaneID = panes.contains(where: { $0.id == tab.focusedPaneID })
            ? tab.focusedPaneID
            : panes[0].id

        return Tab(
            id: tab.id,
            title: tab.title,
            rootLayout: normalizedLayout,
            focusedPaneID: focusedPaneID
        )
    }

    private static func normalizedRestoredLayoutNode(_ node: TabLayoutNode) -> TabLayoutNode {
        switch node {
        case .paneStack(let paneStack):
            let panes = paneStack.panes.map(sanitizedPaneForPersistence)
            let focusedPaneID = panes.contains(where: { $0.id == paneStack.focusedPaneID })
                ? paneStack.focusedPaneID
                : panes[0].id
            return .paneStack(
                PaneStack(
                    id: paneStack.id,
                    panes: panes,
                    focusedPaneID: focusedPaneID
                )
            )
        case .split(let axis, let children):
            let normalizedChildren = children.map(normalizedRestoredLayoutNode)
            return .split(axis: axis, children: normalizedChildren)
        }
    }

    private static func basePaneTitle(for path: String) -> String {
        let directoryURL = URL(fileURLWithPath: path)
        return directoryURL.lastPathComponent.isEmpty ? "OpenMUX" : directoryURL.lastPathComponent
    }

    private func closeWorkspaces(
        relativeTo workspaceID: WorkspaceID,
        matchingRange: (_ targetIndex: Int, _ totalCount: Int) -> Range<Int>
    ) throws -> Workspace? {
        lock.lock()
        guard let targetIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            lock.unlock()
            return nil
        }
        let removableIndexes = Array(matchingRange(targetIndex, workspaces.count))
        let removableIDs = removableIndexes.map { workspaces[$0].id }
        lock.unlock()

        guard removableIDs.isEmpty == false else {
            return activeWorkspace()
        }

        return try removeWorkspaces(
            matching: { removableIDs.contains($0.id) },
            preferredActiveWorkspaceID: workspaceID
        )
    }

    private func removeWorkspaces(
        matching shouldRemove: (Workspace) -> Bool,
        preferredActiveWorkspaceID: WorkspaceID?
    ) throws -> Workspace? {
        var removedWorkspaces: [Workspace] = []
        var updatedWorkspace: Workspace?

        lock.lock()
        let survivingWorkspaces = workspaces.filter { workspace in
            if shouldRemove(workspace) {
                removedWorkspaces.append(workspace)
                return false
            }
            return true
        }

        guard removedWorkspaces.isEmpty == false, survivingWorkspaces.isEmpty == false else {
            lock.unlock()
            return nil
        }

        workspaces = survivingWorkspaces
        if let previousWorkspaceID, removedWorkspaces.contains(where: { $0.id == previousWorkspaceID }) {
            self.previousWorkspaceID = nil
        }

        if let preferredActiveWorkspaceID,
           let preferredIndex = workspaces.firstIndex(where: { $0.id == preferredActiveWorkspaceID }) {
            setActiveWorkspaceID(workspaces[preferredIndex].id, recordPrevious: false)
            updatedWorkspace = workspaces[preferredIndex]
        } else if let activeWorkspaceID,
                  let existingIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) {
            updatedWorkspace = workspaces[existingIndex]
        } else if let firstWorkspace = workspaces.first {
            setActiveWorkspaceID(firstWorkspace.id, recordPrevious: false)
            updatedWorkspace = firstWorkspace
        }
        lock.unlock()

        for removedWorkspace in removedWorkspaces {
            for pane in removedWorkspace.tabs.flatMap(\.panes) {
                try bridge.teardown(paneID: pane.id)
            }

            try hookRunner.emit(
                HookInvocation(
                    category: .lifecycle,
                    name: "workspace-closed",
                    workspaceID: removedWorkspace.id,
                    payload: .object(["path": .string(removedWorkspace.rootPath)])
                )
            )
        }

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }
        return updatedWorkspace
    }

    private func closePaneTabs(
        relativeTo paneID: PaneID,
        targetIDs: (_ panes: [Pane], _ targetIndex: Int) -> [PaneID]
    ) throws -> Workspace? {
        var removedPanes: [Pane] = []
        var targetStackID: PaneStackID?
        var updatedWorkspace: Workspace?
        var updatedWorkspaceID: WorkspaceID?
        var updatedTabID: TabID?

        lock.lock()
        for workspaceIndex in workspaces.indices {
            for tabIndex in workspaces[workspaceIndex].tabs.indices {
                guard let paneStack = workspaces[workspaceIndex].tabs[tabIndex].rootLayout.paneStack(containingPaneID: paneID),
                      let targetIndex = paneStack.panes.firstIndex(where: { $0.id == paneID })
                else {
                    continue
                }

                let removalIDs = targetIDs(paneStack.panes, targetIndex)
                guard removalIDs.isEmpty == false else {
                    return workspaces[workspaceIndex]
                }

                targetStackID = paneStack.id
                for removalID in removalIDs {
                    if let removedPane = workspaces[workspaceIndex].closePane(removalID) {
                        removedPanes.append(removedPane)
                    }
                }

                updatedWorkspace = workspaces[workspaceIndex]
                updatedWorkspaceID = workspaces[workspaceIndex].id
                updatedTabID = workspaces[workspaceIndex].tabs[tabIndex].id
                break
            }
            if updatedWorkspace != nil {
                break
            }
        }

        guard let updatedWorkspace,
              let updatedWorkspaceID,
              let updatedTabID
        else {
            lock.unlock()
            return nil
        }

        lock.unlock()
        for removedPane in removedPanes {
            try bridge.teardown(paneID: removedPane.id)
            try hookRunner.emit(
                HookInvocation(
                    category: .session,
                    name: "pane-tab-closed",
                    workspaceID: updatedWorkspaceID,
                    tabID: updatedTabID,
                    paneID: removedPane.id,
                    sessionID: removedPane.session.id,
                    payload: .object([
                        "paneStackID": targetStackID.map { .string($0.rawValue) } ?? .null,
                    ])
                )
            )
        }
        onChange?(updatedWorkspace)

        return updatedWorkspace
    }
}
