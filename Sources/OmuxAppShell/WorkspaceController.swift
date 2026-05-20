import AppKit
import Foundation
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxHooks
import OmuxAIStatusPlugin
import OmuxMarkdownPreviewPlugin
import OmuxTerminalBridge

private struct CommandAutomationContext: Sendable {
    let command: String
    let cwd: String?
}

private struct PaneHistoryTarget: Sendable {
    let workspaceID: WorkspaceID
    let workspaceName: String
    let tabID: TabID
    let tabTitle: String
    let paneStackID: PaneStackID?
    let paneID: PaneID
    let paneTitle: String
    let sessionID: SessionID
    let workingDirectory: String?
    let persistedHistory: PaneScrollbackSnapshot?
}

private struct WorkspaceLookupLocation: Sendable {
    let workspaceIndex: Int
    let tabIndex: Int?
    let floatingPaneModalIndex: Int?
    let paneIndex: Int
}

private struct WorkspacePaneResolution: Sendable {
    let workspace: Workspace
    let tab: Tab?
    let floatingPaneModal: FloatingPaneModal?
    let pane: Pane
}

public struct PaneTabCloseCandidate: Equatable, Sendable {
    public let paneID: PaneID
    public let workingDirectory: String
}

public struct ExtensionPaneActionResult: Sendable {
    public let workspace: Workspace
    public let tabID: TabID?
    public let paneStackID: PaneStackID?
    public let floatingPaneModalID: FloatingPaneModalID?
    public let pane: Pane
}

public final class WorkspaceController: @unchecked Sendable {
    private let lock = NSLock()
    private let bridge: GhosttyTerminalBridge
    private let hookRunner: ExternalHookRunner
    private var persistedScrollback: OmuxConfigTerminal.PersistedScrollback
    private var markdownPreviewConfiguration: OmuxConfigPlugins.MarkdownPreview
    private var aiStatusConfiguration: OmuxConfigPlugins.AIStatus
    private var paneConfiguration: OmuxConfigUI.Panes
    private var workspaceShellEnvironment: WorkspaceShellEnvironment
    private let scrollbackReplayStore: ScrollbackReplayStore?
    private let scrollbackReplayWrapperStore: ScrollbackReplayWrapperStore?
    private var defaultWorkspaceRootPath: String
    private var workspaces: [Workspace] = [] {
        didSet { lookupIndexesDirty = true }
    }
    private var activeWorkspaceID: WorkspaceID?
    private var previousWorkspaceID: WorkspaceID?
    private var lastNotification: NotificationRequest?
    private var updateAvailability: OpenMUXUpdateAvailability?
    private var commandContextBySession: [SessionID: CommandAutomationContext] = [:]
    private var historyClearSuppressionByPane: [PaneID: String] = [:]
    private var progressIdleClearTokens: [PaneID: UUID] = [:]
    private var aiStatusManagedAdapterByPaneID: [PaneID: String] = [:]
    private var pendingTerminalStateWorkspaceIDs: Set<WorkspaceID> = []
    private var terminalStateChangeUpdateScheduled = false
    private var deliveredTerminalDisplayTitleByPane: [PaneID: String] = [:]
    private var lastTerminalDisplayTitleUpdateByPane: [PaneID: Date] = [:]
    private var pendingTerminalDisplayTitlePaneIDs: Set<PaneID> = []
    private var terminalDisplayTitleUpdateScheduled = false
    private var markdownPreviewWatchTasks: [PaneID: (token: UUID, task: Task<Void, Never>)] = [:]
    private var workspaceIndexByID: [WorkspaceID: Int] = [:]
    private var tabLocationByID: [TabID: (workspaceIndex: Int, tabIndex: Int)] = [:]
    private var paneLocationByID: [PaneID: WorkspaceLookupLocation] = [:]
    private var sessionLocationByID: [SessionID: WorkspaceLookupLocation] = [:]
    private var lookupIndexesDirty = true
    private let progressIdleClearDelay: TimeInterval
    private let terminalStateChangeCoalescingDelay: TimeInterval
    private let terminalDisplayTitleUpdateMinimumInterval: TimeInterval
    private var controlPlaneEventHandler: ((ControlPlaneEvent) -> Void)?
    private lazy var terminalActionCoordinator = TerminalActionCoordinator(
        bridge: bridge,
        controller: self,
        hookRunner: hookRunner
    )

    public var onChange: ((Workspace) -> Void)?
    public var onControlPlaneEvent: ((ControlPlaneEvent) -> Void)? {
        get { controlPlaneEventHandler }
        set { controlPlaneEventHandler = newValue }
    }
    public var onTerminalEvent: ((ControlPlaneEvent) -> Void)? {
        get { controlPlaneEventHandler }
        set { controlPlaneEventHandler = newValue }
    }

    public init(
        bridge: GhosttyTerminalBridge,
        hookRunner: ExternalHookRunner,
        defaultWorkspaceRootPath: String = OmuxWorkspacePathResolver.defaultRootPath,
        persistedScrollback: OmuxConfigTerminal.PersistedScrollback = OmuxConfigTerminal.PersistedScrollback(),
        isolateShellHistory: Bool = OmuxConfigWorkspace.defaultIsolateShellHistory,
        workspaceShellStateDirectoryURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("OpenMUX-WorkspaceShellHistory", isDirectory: true),
        paneConfiguration: OmuxConfigUI.Panes = OmuxConfigUI.Panes(),
        markdownPreviewConfiguration: OmuxConfigPlugins.MarkdownPreview = OmuxConfigPlugins.MarkdownPreview(),
        aiStatusConfiguration: OmuxConfigPlugins.AIStatus = OmuxConfigPlugins.AIStatus(enabled: false),
        scrollbackReplayStore: ScrollbackReplayStore? = nil,
        scrollbackReplayWrapperStore: ScrollbackReplayWrapperStore? = nil,
        progressIdleClearDelay: TimeInterval = 3,
        terminalStateChangeCoalescingDelay: TimeInterval = 0.05,
        terminalDisplayTitleUpdateMinimumInterval: TimeInterval = 0.5
    ) {
        self.bridge = bridge
        self.hookRunner = hookRunner
        self.persistedScrollback = persistedScrollback
        self.workspaceShellEnvironment = WorkspaceShellEnvironment(
            isolateShellHistory: isolateShellHistory,
            stateDirectoryURL: workspaceShellStateDirectoryURL
        )
        self.paneConfiguration = paneConfiguration
        self.markdownPreviewConfiguration = markdownPreviewConfiguration
        self.aiStatusConfiguration = aiStatusConfiguration
        self.scrollbackReplayStore = scrollbackReplayStore
        self.scrollbackReplayWrapperStore = scrollbackReplayWrapperStore
        self.defaultWorkspaceRootPath = defaultWorkspaceRootPath
        self.progressIdleClearDelay = progressIdleClearDelay
        self.terminalStateChangeCoalescingDelay = terminalStateChangeCoalescingDelay
        self.terminalDisplayTitleUpdateMinimumInterval = terminalDisplayTitleUpdateMinimumInterval
        _ = terminalActionCoordinator
    }

    private func withControllerLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func workspaceShellEnvironmentSnapshot() -> WorkspaceShellEnvironment {
        withControllerLock { workspaceShellEnvironment }
    }

    public func openWorkspace(at path: String) throws -> Workspace {
        let generatedWorkspaceName = withControllerLock { nextGeneratedWorkspaceName() }

        let workspaceID = WorkspaceID()
        let paneTitle = Self.basePaneTitle(for: path)
        let shellEnvironment = workspaceShellEnvironmentSnapshot()
        let pane = try makePane(
            title: paneTitle,
            workingDirectory: path,
            workspaceID: workspaceID,
            workspaceRootPath: path,
            shellEnvironment: shellEnvironment
        )
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)

        let workspace = Workspace(
            id: workspaceID,
            generatedName: generatedWorkspaceName,
            rootPath: path,
            tabs: [tab],
            focusedTabID: tab.id
        )

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(
            session: launchSession(for: pane, workspace: workspace, shellEnvironment: shellEnvironment),
            to: pane
        )

        lock.lock()
        workspaces.append(workspace)
        setActiveWorkspaceID(workspace.id)
        lock.unlock()

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .workspaceOpened,
                workspaceID: workspace.id,
                tabID: tab.id,
                paneID: pane.id,
                sessionID: pane.session.id,
                payload: .object(["path": .string(path)])
            )
        )
        onChange?(workspace)

        try hookRunner.emit(
            HookInvocation(
                category: .lifecycle,
                name: "workspace-opened",
                workspaceID: workspace.id,
                tabID: tab.id,
                paneID: pane.id,
                sessionID: pane.session.id,
                payload: .object(["path": .string(path)])
            )
        )
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

    public func terminalHistory(_ request: ControlPlaneHistoryRequest) -> ControlPlaneHistoryResponse? {
        let targets: [PaneHistoryTarget]
        lock.lock()
        switch request.scope {
        case .activeWorkspace:
            if let activeWorkspaceID,
               let workspace = workspaces.first(where: { $0.id == activeWorkspaceID }) {
                targets = Self.historyTargets(in: workspace)
            } else {
                targets = []
            }
        case .pane(let paneID):
            guard let target = workspaces.lazy.compactMap({ Self.historyTarget(paneID: paneID, in: $0) }).first else {
                lock.unlock()
                return nil
            }
            targets = [target]
        case .all:
            targets = workspaces.flatMap(Self.historyTargets(in:))
        }
        lock.unlock()

        let items = targets.map { target in
            let liveSnapshot = bridge.terminalTextSnapshot(
                for: target.paneID,
                maxBytes: request.maxBytes,
                maxLines: request.maxLines
            )
            if liveSnapshot.isAvailable {
                if let snapshot = PaneScrollbackSnapshot.combined(
                    target.persistedHistory,
                    liveSnapshot.scrollbackSnapshot,
                    maxBytes: request.maxBytes,
                    maxLines: request.maxLines
                ) {
                    return target.historyItem(text: snapshot.text, truncated: snapshot.truncated)
                }
                return target.historyItem(text: "", truncated: false)
            }

            if let persistedHistory = target.persistedHistory {
                return target.historyItem(text: persistedHistory.text, truncated: persistedHistory.truncated)
            }

            let reason = liveSnapshot.unavailableReason ?? "history unavailable"
            return target.historyItem(text: "", truncated: false, unavailable: reason)
        }

        return ControlPlaneHistoryResponse(
            scope: request.scope,
            maxBytes: request.maxBytes,
            maxLines: request.maxLines,
            items: items
        )
    }

    public func clearTerminalHistory(_ request: ControlPlaneHistoryClearRequest) -> ControlPlaneHistoryClearResponse? {
        lock.lock()
        guard let paneIDs = historyClearPaneIDsLocked(target: request.target) else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let fingerprints = Dictionary(uniqueKeysWithValues: paneIDs.map { paneID in
            let text = bridge.scrollbackSnapshot(
                for: paneID,
                maxBytes: PaneScrollbackSnapshot.defaultMaxBytes,
                maxLines: PaneScrollbackSnapshot.defaultMaxLines
            )?.text ?? ""
            return (paneID, text)
        })
        for paneID in paneIDs {
            _ = try? bridge.clearScreenAndScrollback(for: paneID)
        }

        lock.lock()
        var clearedCount = 0
        var changedWorkspace: Workspace?
        for paneID in paneIDs {
            for workspaceIndex in workspaces.indices {
                guard workspaces[workspaceIndex].updatePane(paneID, transform: { pane in
                    pane.terminalState.restoredScrollback = nil
                }) else {
                    continue
                }

                historyClearSuppressionByPane[paneID] = fingerprints[paneID] ?? ""
                clearedCount += 1
                if workspaces[workspaceIndex].id == activeWorkspaceID || changedWorkspace == nil {
                    changedWorkspace = workspaces[workspaceIndex]
                }
                break
            }
        }
        lock.unlock()

        if let changedWorkspace {
            onChange?(changedWorkspace)
        }

        return ControlPlaneHistoryClearResponse(clearedCount: clearedCount, target: request.target)
    }

    public func resolveTerminalTarget(_ target: ControlPlaneTerminalTarget) -> ControlPlaneTerminalContext? {
        lock.lock()
        defer { lock.unlock() }
        return resolveTerminalTargetLocked(target)
    }

    func persistenceSnapshot(
        mode: WorkspacePersistenceSnapshotMode = .includeScrollback()
    ) -> WorkspacePersistenceSnapshot? {
        lock.lock()
        let currentWorkspaces = workspaces
        let storedActiveWorkspaceID = activeWorkspaceID
        let historyClearSuppression = historyClearSuppressionByPane
        lock.unlock()

        let storedWorkspaces = currentWorkspaces.map {
            sanitizedWorkspaceForPersistence($0, mode: mode, historyClearSuppression: historyClearSuppression)
        }

        guard storedWorkspaces.isEmpty == false else {
            return nil
        }

        return WorkspacePersistenceSnapshot(
            workspaces: storedWorkspaces,
            activeWorkspaceID: storedActiveWorkspaceID
        )
    }

    func persistenceSnapshotForConfiguredPersistence() -> WorkspacePersistenceSnapshot? {
        let persistedScrollback = currentPersistedScrollback()
        let mode: WorkspacePersistenceSnapshotMode = persistedScrollback.enabled
            ? .includeScrollback(maxBytes: persistedScrollback.maxBytes, maxLines: persistedScrollback.maxLines)
            : .layoutOnly
        return persistenceSnapshot(mode: mode)
    }

    @discardableResult
    func restorePersistedState(_ snapshot: WorkspacePersistenceSnapshot) throws -> Workspace? {
        let restoredWorkspaces = snapshot.workspaces.compactMap(Self.normalizedRestoredWorkspace)
        guard restoredWorkspaces.isEmpty == false else {
            return nil
        }

        let restoredActiveWorkspaceID = snapshot.activeWorkspaceID.flatMap { activeID in
            restoredWorkspaces.contains(where: { $0.id == activeID }) ? activeID : nil
        } ?? restoredWorkspaces.first?.id

        let existingPaneIDs = allWorkspaces().flatMap(\.panes).map(\.id)
        for paneID in existingPaneIDs {
            try? bridge.teardown(paneID: paneID)
        }

        if let restoredActiveWorkspace = restoredActiveWorkspaceID.flatMap({ activeID in
            restoredWorkspaces.first(where: { $0.id == activeID })
        }) {
            try ensureTerminalSurfaces(in: restoredActiveWorkspace)
        }

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
    public func ensureVisibleTerminalSurfaces(for workspaceID: WorkspaceID) throws -> Workspace? {
        lock.lock()
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        try ensureTerminalSurfaces(in: workspace)
        return workspace
    }

    private func launchSession(for pane: Pane, workspace: Workspace) throws -> SessionDescriptor {
        try launchSession(
            forRestoredPane: pane,
            workspaceID: workspace.id,
            workspaceRootPath: workspace.rootPath,
            shellEnvironment: workspaceShellEnvironmentSnapshot()
        )
    }

    private func launchSession(
        for pane: Pane,
        workspace: Workspace,
        shellEnvironment: WorkspaceShellEnvironment
    ) throws -> SessionDescriptor {
        try launchSession(
            forRestoredPane: pane,
            workspaceID: workspace.id,
            workspaceRootPath: workspace.rootPath,
            shellEnvironment: shellEnvironment
        )
    }

    private func launchSession(
        forRestoredPane pane: Pane,
        workspaceID: WorkspaceID,
        workspaceRootPath: String,
        shellEnvironment: WorkspaceShellEnvironment
    ) throws -> SessionDescriptor {
        guard let session = pane.terminalSession else {
            preconditionFailure("Cannot launch a terminal session for extension pane \(pane.id.rawValue)")
        }
        try shellEnvironment.prepareHistoryStorage(for: workspaceID)
        let workspaceSession = shellEnvironment.launchSession(
            from: session,
            workspaceID: workspaceID,
            workspaceRootPath: workspaceRootPath
        )

        let persistedScrollback = currentPersistedScrollback()
        guard persistedScrollback.enabled,
              let scrollbackReplayStore,
              let scrollbackReplayWrapperStore,
              let replay = scrollbackReplayStore.prepareReplay(
                  for: pane.terminalState.restoredScrollback,
                  maxBytes: persistedScrollback.maxBytes,
                  maxLines: persistedScrollback.maxLines
              ),
              let launch = scrollbackReplayWrapperStore.prepareLaunch(baseSession: workspaceSession, replay: replay)
        else {
            return workspaceSession
        }

        return launch.session
    }

    private func ensureTerminalSurfaces(in workspace: Workspace) throws {
        for pane in Self.visibleTerminalPanes(in: workspace) {
            try ensureTerminalSurface(
                for: pane,
                workspaceID: workspace.id,
                workspaceRootPath: workspace.rootPath
            )
        }
    }

    @discardableResult
    private func ensureTerminalSurface(
        for pane: Pane,
        workspaceID: WorkspaceID,
        workspaceRootPath: String
    ) throws -> Bool {
        guard pane.isTerminal else {
            return false
        }
        guard bridge.surface(for: pane.id) == nil else {
            return false
        }

        _ = try bridge.attach(
            session: try launchSession(
                forRestoredPane: pane,
                workspaceID: workspaceID,
                workspaceRootPath: workspaceRootPath,
                shellEnvironment: workspaceShellEnvironmentSnapshot()
            ),
            to: pane
        )
        return true
    }

    @discardableResult
    private func ensureTerminalSurface(for paneID: PaneID) throws -> Bool {
        lock.lock()
        guard let location = paneLocationLocked(for: paneID),
              let resolution = workspacePaneLocked(at: location)
        else {
            lock.unlock()
            return false
        }
        let workspace = resolution.workspace
        let pane = resolution.pane
        lock.unlock()

        return try ensureTerminalSurface(for: pane, workspaceID: workspace.id, workspaceRootPath: workspace.rootPath)
    }

    private static func visibleTerminalPanes(in workspace: Workspace) -> [Pane] {
        let focusedTabPanes = (workspace.focusedTab ?? workspace.tabs.first)?.panes ?? []
        let floatingPanes = workspace.floatingPaneModals.flatMap(\.panes)
        return (focusedTabPanes + floatingPanes).filter(\.isTerminal)
    }

    private func currentPersistedScrollback() -> OmuxConfigTerminal.PersistedScrollback {
        lock.lock()
        defer { lock.unlock() }
        return persistedScrollback
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

        let focusedPane = updatedWorkspace.focusedPane
        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-focused",
                workspaceID: updatedWorkspace.id,
                sessionID: sessionID
            )
        )

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .sessionFocused,
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: focusedPane?.id,
                sessionID: sessionID,
                payload: .object([:])
            )
        )
        onChange?(updatedWorkspace)
        return true
    }

    @discardableResult
    public func focus(target: ControlPlaneTerminalTarget) throws -> ControlPlaneTerminalContext? {
        guard let context = resolveTerminalTarget(target) else {
            return nil
        }

        if try focus(sessionID: context.sessionID) {
            return resolveTerminalTarget(.session(context.sessionID)) ?? context
        }

        return nil
    }

    public func restore(workspaceID: WorkspaceID) -> Workspace? {
        lock.lock()
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            lock.unlock()
            return nil
        }

        setActiveWorkspaceID(workspace.id)
        lock.unlock()

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .workspaceRestored,
                workspaceID: workspace.id,
                payload: .object([:])
            )
        )
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

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .notificationRaised,
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

    func currentUpdateAvailability() -> OpenMUXUpdateAvailability? {
        lock.lock()
        defer { lock.unlock() }
        return updateAvailability
    }

    func setUpdateAvailability(_ availability: OpenMUXUpdateAvailability?) {
        lock.lock()
        updateAvailability = availability
        let workspace = activeWorkspaceID.flatMap { activeID in
            workspaces.first { $0.id == activeID }
        }
        lock.unlock()

        if let workspace {
            onChange?(workspace)
        }
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

    public func canMoveActiveWorkspaceUp() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let activeWorkspaceIndex else {
            return false
        }
        return activeWorkspaceIndex > 0
    }

    public func canMoveActiveWorkspaceDown() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let activeWorkspaceIndex else {
            return false
        }
        return activeWorkspaceIndex < workspaces.index(before: workspaces.endIndex)
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

    public func canClosePaneTab() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = activeWorkspaceIndex else { return false }
        let panesCount = workspaces[index].focusedPaneStack?.panes.count ?? 0
        let tabsCount = workspaces[index].tabs.count
        let tabPanesCount = workspaces[index].focusedTab?.panes.count ?? 0
        return panesCount > 1 || tabsCount > 1 || tabPanesCount > 1
    }

    public func canFocusPaneTab() -> Bool {
        canClosePaneTab()
    }

    public func paneTabCloseCandidate(paneID: PaneID? = nil) -> PaneTabCloseCandidate? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = activeWorkspaceIndex else { return nil }
        let targetPaneID = paneID ?? workspaces[index].focusedPane?.id
        guard let targetPaneID,
              let location = paneLocationLocked(for: targetPaneID),
              let pane = workspacePaneLocked(at: location)?.pane,
              let workingDirectory = Self.terminalWorkingDirectory(for: pane)
        else {
            return nil
        }
        return PaneTabCloseCandidate(paneID: targetPaneID, workingDirectory: workingDirectory)
    }

    public func hasOtherTerminalPane(
        inside directory: String,
        excluding excludedPaneID: PaneID
    ) -> Bool {
        let normalizedDirectory = Self.normalizedDirectoryPath(directory)
        lock.lock()
        defer { lock.unlock() }
        return workspaces.contains { workspace in
            workspace.panes.contains { pane in
                guard pane.id != excludedPaneID,
                      let workingDirectory = Self.terminalWorkingDirectory(for: pane)
                else {
                    return false
                }
                return Self.normalizedDirectoryPath(workingDirectory).isContained(in: normalizedDirectory)
            }
        }
    }

    public func canFocusPane() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeWorkspaceIndex.flatMap { index in
            workspaces[index].focusedTab?.visiblePaneIDs.count
        }.map { $0 > 1 } ?? false
    }

    public func canEqualizeSplits() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeWorkspaceIndex.map { workspaces[$0].hasFocusedTabSplits } ?? false
    }

    public func canResizeSplit(_ direction: PaneSplitResizeDirection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeWorkspaceIndex.map { workspaces[$0].canResizeFocusedSplit(direction) } ?? false
    }

    public var terminalBridge: GhosttyTerminalBridge {
        bridge
    }

    public func updateDefaultWorkspaceRootPath(_ path: String) {
        lock.lock()
        defaultWorkspaceRootPath = path
        lock.unlock()
    }

    public func updatePersistedScrollback(_ persistedScrollback: OmuxConfigTerminal.PersistedScrollback) {
        lock.lock()
        self.persistedScrollback = persistedScrollback
        lock.unlock()
    }

    public func updateShellHistoryIsolation(_ isolateShellHistory: Bool) {
        withControllerLock {
            workspaceShellEnvironment.isolateShellHistory = isolateShellHistory
        }
    }

    public func updateMarkdownPreviewConfiguration(_ configuration: OmuxConfigPlugins.MarkdownPreview) {
        lock.lock()
        markdownPreviewConfiguration = configuration
        lock.unlock()
    }

    public func updateAIStatusConfiguration(_ configuration: OmuxConfigPlugins.AIStatus) {
        lock.lock()
        aiStatusConfiguration = configuration
        if configuration.enabled == false {
            aiStatusManagedAdapterByPaneID.removeAll()
        }
        lock.unlock()
    }

    public func updatePaneConfiguration(_ configuration: OmuxConfigUI.Panes) {
        var pendingSchedules: [(PaneID, UUID)] = []
        lock.lock()
        paneConfiguration = configuration
        progressIdleClearTokens.removeAll()

        switch configuration.idleStatusClear {
        case .onFocus:
            if let activeWorkspaceIndex,
               let focusedPaneID = workspaces[activeWorkspaceIndex].focusedPane?.id,
               clearIdleProgressLocked(for: focusedPaneID, workspaceIndex: activeWorkspaceIndex) {
                let updatedWorkspace = workspaces[activeWorkspaceIndex]
                lock.unlock()
                onChange?(updatedWorkspace)
                return
            }
        case .afterDelay:
            for workspace in workspaces {
                for pane in workspace.tabs.flatMap(\.panes) where pane.terminalState.progress?.state == .paused {
                    let token = UUID()
                    progressIdleClearTokens[pane.id] = token
                    pendingSchedules.append((pane.id, token))
                }
            }
        case .never:
            break
        }
        lock.unlock()

        for (paneID, token) in pendingSchedules {
            scheduleProgressIdleClear(for: paneID, token: token)
        }
    }

    @discardableResult
    public func handleTerminalTextActivation(_ request: TerminalTextActivationRequest) -> Bool {
        guard let context = resolvedTerminalTextActivationContext(for: request) else {
            return false
        }

        emitTerminalTextActivationHook(context)
        publishTerminalTextActivationEvent(context)

        guard let resolvedPath = context.resolvedPath,
              shouldOpenMarkdownPreview(for: resolvedPath)
        else {
            return false
        }

        openMarkdownPreview(for: resolvedPath)
        return true
    }

    public func canHandleTerminalTextActivation(_ request: TerminalTextActivationRequest) -> Bool {
        guard let context = resolvedTerminalTextActivationContext(for: request),
              let resolvedPath = context.resolvedPath
        else {
            return false
        }
        return shouldOpenMarkdownPreview(for: resolvedPath)
    }

    private func resolvedTerminalTextActivationContext(
        for request: TerminalTextActivationRequest
    ) -> TerminalTextActivationContext? {
        let snapshot = bridge.terminalTextSnapshot(for: request.paneID, maxBytes: 64 * 1024, maxLines: request.terminalSize.rows)
        guard snapshot.unavailableReason == nil,
              let hit = TerminalTextActivationResolver.hit(in: snapshot.text, request: request)
        else {
            return nil
        }

        return terminalTextActivationContext(for: request, hit: hit)
    }

    @discardableResult
    public func createWorkspace() throws -> Workspace {
        lock.lock()
        let rootPath = defaultWorkspaceRootPath
        lock.unlock()
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
        let creation = try withControllerLock { () -> (pane: Pane, tab: Tab, workspace: Workspace, shellEnvironment: WorkspaceShellEnvironment)? in
            guard let index = activeWorkspaceIndex else {
                return nil
            }

            let workingDirectory = workspaces[index].rootPath
            let shellEnvironment = workspaceShellEnvironment
            let pane = try makePane(
                title: "Shell",
                workingDirectory: workingDirectory,
                workspaceID: workspaces[index].id,
                workspaceRootPath: workspaces[index].rootPath,
                shellEnvironment: shellEnvironment
            )
            let tab = Tab(title: "Tab \(workspaces[index].tabs.count + 1)", panes: [pane], focusedPaneID: pane.id)
            workspaces[index].appendTab(tab)
            return (pane, tab, workspaces[index], shellEnvironment)
        }

        guard let creation else {
            return nil
        }
        let pane = creation.pane
        let tab = creation.tab
        let updatedWorkspace = creation.workspace
        let shellEnvironment = creation.shellEnvironment

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(
            session: launchSession(for: pane, workspace: updatedWorkspace, shellEnvironment: shellEnvironment),
            to: pane
        )

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

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .tabCreated,
                workspaceID: updatedWorkspace.id,
                tabID: tab.id,
                paneID: pane.id,
                sessionID: pane.session.id,
                payload: .object([:])
            )
        )
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func splitFocusedPane(axis: PaneSplitAxis = .columns) throws -> Workspace? {
        let split = try withControllerLock { () -> (pane: Pane, workspace: Workspace, shellEnvironment: WorkspaceShellEnvironment)? in
            guard let index = activeWorkspaceIndex,
                  let focusedPane = workspaces[index].focusedPane
            else {
                return nil
            }

            let shellEnvironment = workspaceShellEnvironment
            let sourceWorkingDirectory = focusedPane.terminalState.reportedWorkingDirectory
                ?? focusedPane.terminalSession?.workingDirectory
                ?? workspaces[index].rootPath
            let pane = try makePane(
                title: Self.basePaneTitle(for: sourceWorkingDirectory),
                workingDirectory: sourceWorkingDirectory,
                workspaceID: workspaces[index].id,
                workspaceRootPath: workspaces[index].rootPath,
                shellEnvironment: shellEnvironment
            )
            let success = workspaces[index].appendPaneToFocusedTab(pane, axis: axis)
            return success ? (pane, workspaces[index], shellEnvironment) : nil
        }

        guard let split else {
            return nil
        }
        let pane = split.pane
        let updatedWorkspace = split.workspace
        let shellEnvironment = split.shellEnvironment

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(
            session: launchSession(for: pane, workspace: updatedWorkspace, shellEnvironment: shellEnvironment),
            to: pane
        )

        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-created",
                workspaceID: updatedWorkspace.id,
                paneID: pane.id,
                sessionID: pane.terminalSession?.id
            )
        )

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .paneSplit,
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: pane.id,
                sessionID: pane.terminalSession?.id,
                payload: .object(["axis": .string(axis.rawValue)])
            )
        )
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func movePaneTabToSplit(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        targetStackID: PaneStackID,
        direction: PaneSplitDropDirection
    ) throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let success = workspaces[index].movePaneTabToSplit(
            paneID: paneID,
            sourceStackID: sourceStackID,
            targetStackID: targetStackID,
            direction: direction
        )
        let updatedWorkspace = success ? workspaces[index] : nil
        lock.unlock()

        guard let updatedWorkspace else { return nil }
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func movePaneTabToStack(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        targetStackID: PaneStackID
    ) throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let success = workspaces[index].movePaneTabToExistingStack(
            paneID: paneID,
            sourceStackID: sourceStackID,
            targetStackID: targetStackID
        )
        let updatedWorkspace = success ? workspaces[index] : nil
        lock.unlock()

        guard let updatedWorkspace else { return nil }
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func reorderPaneTabInStack(
        paneID: PaneID,
        stackID: PaneStackID,
        insertionIndex: Int
    ) -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let success = workspaces[index].reorderPaneTabInStack(
            paneID: paneID,
            stackID: stackID,
            insertionIndex: insertionIndex
        )
        let updatedWorkspace = success ? workspaces[index] : nil
        lock.unlock()

        guard let updatedWorkspace else { return nil }
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func updateFloatingPaneModalFrame(
        modalID: FloatingPaneModalID,
        frame: FloatingPaneModalFrame
    ) -> Workspace? {
        lock.lock()
        guard let workspaceIndex = workspaces.firstIndex(where: { workspace in
            workspace.floatingPaneModals.contains(where: { $0.id == modalID })
        }),
        workspaces[workspaceIndex].updateFloatingPaneModalFrame(modalID: modalID, frame: frame)
        else {
            lock.unlock()
            return nil
        }

        let updatedWorkspace = workspaces[workspaceIndex]
        lock.unlock()
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func dockFloatingPaneModalToRootSplit(
        modalID: FloatingPaneModalID,
        direction: PaneSplitDropDirection
    ) -> Workspace? {
        lock.lock()
        guard let workspaceIndex = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let success = workspaces[workspaceIndex].moveFloatingPaneModalToRootSplit(
            modalID: modalID,
            direction: direction
        )
        let updatedWorkspace = success ? workspaces[workspaceIndex] : nil
        lock.unlock()

        guard let updatedWorkspace else { return nil }
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func movePaneTabToFloatingModal(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        frame: FloatingPaneModalFrame = FloatingPaneModalFrame()
    ) -> Workspace? {
        lock.lock()
        guard let workspaceIndex = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let movedModal = workspaces[workspaceIndex].moveDockedPaneToFloatingModal(
            paneID: paneID,
            sourceStackID: sourceStackID,
            frame: frame
        )
        let updatedWorkspace = movedModal == nil ? nil : workspaces[workspaceIndex]
        lock.unlock()

        guard let updatedWorkspace else { return nil }
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func movePaneTabToRootSplit(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        direction: PaneSplitDropDirection
    ) throws -> Workspace? {
        lock.lock()
        guard let index = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }

        let success = workspaces[index].movePaneTabToRootSplit(
            paneID: paneID,
            sourceStackID: sourceStackID,
            direction: direction
        )
        let updatedWorkspace = success ? workspaces[index] : nil
        lock.unlock()

        guard let updatedWorkspace else { return nil }
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func splitPane(
        target: ControlPlaneTerminalTarget?,
        axis: PaneSplitAxis = .columns
    ) throws -> (workspace: Workspace, created: ControlPlaneTerminalContext)? {
        if let target {
            guard try focus(target: target) != nil else {
                return nil
            }
        }

        guard let workspace = try splitFocusedPane(axis: axis),
              let createdPane = workspace.focusedPane,
              let createdSession = createdPane.terminalSession
        else {
            return nil
        }

        return (
            workspace,
            ControlPlaneTerminalContext(
                workspaceID: workspace.id,
                tabID: workspace.focusedTabID,
                paneStackID: workspace.focusedPaneStack?.id,
                paneID: createdPane.id,
                sessionID: createdSession.id
            )
        )
    }

    @discardableResult
    public func createExtensionPane(
        title: String,
        descriptor: ExtensionPaneDescriptor,
        axis: PaneSplitAxis = .columns
    ) -> ExtensionPaneActionResult? {
        let paneTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pane = Pane(
            title: paneTitle.isEmpty ? descriptor.pluginID : paneTitle,
            extensionPane: descriptor
        )

        lock.lock()
        guard let index = activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }
        let createdInModal: FloatingPaneModal?
        if descriptor.presentationStyle == .modal {
            createdInModal = workspaces[index].createFloatingPaneModal(containing: pane)
        } else {
            guard workspaces[index].appendPaneToFocusedTab(pane, axis: axis) else {
                lock.unlock()
                return nil
            }
            createdInModal = nil
        }
        let updatedWorkspace = workspaces[index]
        let result = ExtensionPaneActionResult(
            workspace: updatedWorkspace,
            tabID: createdInModal == nil ? updatedWorkspace.focusedTabID : nil,
            paneStackID: createdInModal?.paneStack.id ?? updatedWorkspace.focusedPaneStack?.id,
            floatingPaneModalID: createdInModal?.id,
            pane: pane
        )
        lock.unlock()

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .extensionPaneCreated,
                workspaceID: updatedWorkspace.id,
                tabID: result.tabID,
                paneID: pane.id,
                payload: .object([
                    "pluginID": .string(descriptor.pluginID),
                    "contentKind": .string(descriptor.contentKind.rawValue),
                    "source": descriptor.source.map(OmuxValue.string) ?? .null,
                ])
            )
        )
        onChange?(updatedWorkspace)
        return result
    }

    @discardableResult
    public func updateExtensionPane(
        paneID: PaneID,
        descriptor: ExtensionPaneDescriptor,
        title: String? = nil
    ) -> ExtensionPaneActionResult? {
        lock.lock()
        var result: ExtensionPaneActionResult?
        for workspaceIndex in workspaces.indices {
            let wasFloating = workspaces[workspaceIndex].floatingPaneModals.contains(where: { modal in
                modal.paneStack.panes.contains(where: { $0.id == paneID })
            })
            let sourceStackID = paneStackID(for: paneID, in: workspaces[workspaceIndex])
            guard workspaces[workspaceIndex].updatePane(paneID, transform: { pane in
                guard pane.extensionPane != nil else {
                    return
                }
                pane.extensionPane = descriptor
                if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    pane.title = title
                }
            }) else {
                continue
            }

            if descriptor.presentationStyle == .modal,
               wasFloating == false,
               let sourceStackID {
                _ = workspaces[workspaceIndex].moveDockedPaneToFloatingModal(
                    paneID: paneID,
                    sourceStackID: sourceStackID
                )
            } else if descriptor.presentationStyle == .paneTab,
                      wasFloating,
                      let sourceStackID {
                if let targetStackID = dockedTargetPaneStackID(in: workspaces[workspaceIndex]) {
                    _ = workspaces[workspaceIndex].movePaneTabToExistingStack(
                        paneID: paneID,
                        sourceStackID: sourceStackID,
                        targetStackID: targetStackID
                    )
                } else {
                    _ = workspaces[workspaceIndex].movePaneTabToRootSplit(
                        paneID: paneID,
                        sourceStackID: sourceStackID,
                        direction: .right
                    )
                }
            }

            guard let pane = workspaces[workspaceIndex].panes.first(where: { $0.id == paneID }),
                  pane.extensionPane != nil
            else {
                break
            }
            let workspace = workspaces[workspaceIndex]
            let floatingPaneModalID = floatingPaneModalID(for: paneID, in: workspace)
            result = ExtensionPaneActionResult(
                workspace: workspace,
                tabID: workspace.tabs.first(where: { $0.panes.contains(where: { $0.id == paneID }) })?.id,
                paneStackID: paneStackID(for: paneID, in: workspace),
                floatingPaneModalID: floatingPaneModalID,
                pane: pane
            )
            break
        }
        lock.unlock()

        guard let result else {
            return nil
        }
        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .extensionPaneUpdated,
                workspaceID: result.workspace.id,
                tabID: result.tabID,
                paneID: result.pane.id,
                payload: .object([
                    "pluginID": .string(descriptor.pluginID),
                    "contentKind": .string(descriptor.contentKind.rawValue),
                    "source": descriptor.source.map(OmuxValue.string) ?? .null,
                ])
            )
        )
        onChange?(result.workspace)
        return result
    }

    @discardableResult
    public func closeExtensionPane(paneID: PaneID) throws -> ExtensionPaneActionResult? {
        lock.lock()
        var result: ExtensionPaneActionResult?
        for workspaceIndex in workspaces.indices {
            guard let pane = workspaces[workspaceIndex].panes.first(where: { $0.id == paneID }),
                  pane.extensionPane != nil
            else {
                continue
            }

            let workspaceBeforeClose = workspaces[workspaceIndex]
            let tabIndex = workspaceBeforeClose.tabs.firstIndex(where: { $0.panes.contains(where: { $0.id == paneID }) })
            let tabID = tabIndex.map { workspaceBeforeClose.tabs[$0].id }
            let paneStackID = paneStackID(for: paneID, in: workspaceBeforeClose)
            let floatingPaneModalID = floatingPaneModalID(for: paneID, in: workspaceBeforeClose)
            let removedPane = if let tabIndex {
                workspaces[workspaceIndex].tabs[tabIndex].removePane(paneID)
            } else {
                workspaces[workspaceIndex].closePane(paneID)
            }
            guard let removedPane,
                  removedPane.extensionPane != nil
            else {
                break
            }

            result = ExtensionPaneActionResult(
                workspace: workspaces[workspaceIndex],
                tabID: tabID,
                paneStackID: paneStackID,
                floatingPaneModalID: floatingPaneModalID,
                pane: removedPane
            )
            break
        }
        lock.unlock()

        guard let result else {
            return nil
        }

        cancelMarkdownPreviewWatch(paneID: result.pane.id)
        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-removed",
                workspaceID: result.workspace.id,
                tabID: result.tabID,
                paneID: result.pane.id
            )
        )
        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .extensionPaneClosed,
                workspaceID: result.workspace.id,
                tabID: result.tabID,
                paneID: result.pane.id,
                payload: .object([
                    "pluginID": .string(result.pane.extensionPane?.pluginID ?? ""),
                    "paneStackID": result.paneStackID.map { .string($0.rawValue) } ?? .null,
                ])
            )
        )
        onChange?(result.workspace)
        return result
    }

    @discardableResult
    public func createPaneTab(
        in paneStackID: PaneStackID? = nil,
        workingDirectory explicitWorkingDirectory: String? = nil,
        title explicitTitle: String? = nil
    ) throws -> Workspace? {
        let creation = try withControllerLock { () -> (pane: Pane, stackID: PaneStackID, workspace: Workspace, shellEnvironment: WorkspaceShellEnvironment)? in
            guard let index = activeWorkspaceIndex else {
                return nil
            }

            let targetStack: PaneStack?
            if let paneStackID {
                targetStack = paneStack(id: paneStackID, in: workspaces[index])
            } else {
                targetStack = workspaces[index].focusedPaneStack
            }

            guard let targetStack, let sourcePane = targetStack.focusedPane else {
                return nil
            }

            let sourceWorkingDirectory = sourcePane.terminalState.reportedWorkingDirectory
                ?? sourcePane.terminalSession?.workingDirectory
                ?? workspaces[index].rootPath
            let workingDirectory = explicitWorkingDirectory ?? sourceWorkingDirectory
            let title = explicitTitle ?? Self.basePaneTitle(for: workingDirectory)
            let shellEnvironment = workspaceShellEnvironment
            let pane = try makePane(
                title: title,
                workingDirectory: workingDirectory,
                workspaceID: workspaces[index].id,
                workspaceRootPath: workspaces[index].rootPath,
                shellEnvironment: shellEnvironment
            )
            let success: Bool
            if let paneStackID {
                success = workspaces[index].createPane(inStack: paneStackID, pane: pane)
            } else {
                success = workspaces[index].createPaneInFocusedStack(pane)
            }
            return success ? (pane, targetStack.id, workspaces[index], shellEnvironment) : nil
        }

        guard let creation else {
            return nil
        }
        let pane = creation.pane
        let targetStackID = creation.stackID
        let updatedWorkspace = creation.workspace
        let shellEnvironment = creation.shellEnvironment

        _ = try bridge.createSurface(for: pane)
        _ = try bridge.attach(
            session: launchSession(for: pane, workspace: updatedWorkspace, shellEnvironment: shellEnvironment),
            to: pane
        )

        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-tab-created",
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: pane.id,
                sessionID: pane.terminalSession?.id,
                payload: .object(["paneStackID": .string(targetStackID.rawValue)])
            )
        )

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .paneTabCreated,
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: pane.id,
                sessionID: pane.terminalSession?.id,
                payload: .object(["paneStackID": .string(targetStackID.rawValue)])
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
        let stackPanesCount = targetStackID.flatMap { paneStack(id: $0, in: workspaces[index])?.panes.count } ?? 0

        let removedPane: Pane
        if stackPanesCount > 1 {
            // Multiple pane tabs in the stack: close just this one.
            guard let pane = targetPaneID.flatMap({ workspaces[index].closePane($0) }) else {
                lock.unlock()
                return nil
            }
            removedPane = pane
        } else {
            // Single-pane stack: close the whole workspace tab, or detach from a split.
            guard let targetPaneID else {
                lock.unlock()
                return nil
            }
            guard let containingTab = workspaces[index].tabs.first(where: { $0.panes.contains(where: { $0.id == targetPaneID }) }) else {
                lock.unlock()
                return nil
            }
            if containingTab.panes.count == 1 {
                guard workspaces[index].tabs.count > 1,
                      let removedTab = workspaces[index].closeTab(containingTab.id),
                      let tabPane = removedTab.panes.first
                else {
                    lock.unlock()
                    return nil
                }
                removedPane = tabPane
            } else {
                guard let tabIndex = workspaces[index].tabs.firstIndex(where: { $0.id == containingTab.id }),
                      let pane = workspaces[index].tabs[tabIndex].removePane(targetPaneID)
                else {
                    lock.unlock()
                    return nil
                }
                removedPane = pane
            }
        }

        let updatedWorkspace = workspaces[index]
        lock.unlock()

        if removedPane.isTerminal {
            try bridge.teardown(paneID: removedPane.id)
        } else if removedPane.extensionPane != nil {
            cancelMarkdownPreviewWatch(paneID: removedPane.id)
        }
        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-tab-closed",
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: removedPane.id,
                sessionID: removedPane.terminalSession?.id,
                payload: .object([
                    "paneStackID": targetStackID.map { .string($0.rawValue) } ?? .null,
                ])
            )
        )

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .paneTabClosed,
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: removedPane.id,
                sessionID: removedPane.terminalSession?.id,
                payload: .object([
                    "paneStackID": targetStackID.map { .string($0.rawValue) } ?? .null,
                ])
            )
        )
        onChange?(updatedWorkspace)
        return updatedWorkspace
    }

    @discardableResult
    public func closePane(paneID: PaneID) throws -> Workspace? {
        lock.lock()
        var removedPane: Pane?
        var updatedWorkspace: Workspace?
        var workspaceID: WorkspaceID?
        var tabID: TabID?
        var paneStackID: PaneStackID?
        var closedPaneTab = false

        for workspaceIndex in workspaces.indices {
            if let tabIndex = workspaces[workspaceIndex].tabs.firstIndex(where: { $0.panes.contains(where: { $0.id == paneID }) }),
               let paneStack = workspaces[workspaceIndex].tabs[tabIndex].rootLayout.paneStack(containingPaneID: paneID) {
                workspaceID = workspaces[workspaceIndex].id
                tabID = workspaces[workspaceIndex].tabs[tabIndex].id
                paneStackID = paneStack.id

                if paneStack.panes.count > 1 {
                    removedPane = workspaces[workspaceIndex].tabs[tabIndex].closePane(paneID)
                    closedPaneTab = true
                } else if workspaces[workspaceIndex].tabs[tabIndex].panes.count > 1 {
                    removedPane = workspaces[workspaceIndex].tabs[tabIndex].removePane(paneID)
                } else if workspaces[workspaceIndex].tabs.count > 1 {
                    removedPane = workspaces[workspaceIndex].closeTab(workspaces[workspaceIndex].tabs[tabIndex].id)?.panes.first
                }
            } else if let modal = workspaces[workspaceIndex].floatingPaneModals.first(where: { $0.paneStack.panes.contains(where: { $0.id == paneID }) }) {
                workspaceID = workspaces[workspaceIndex].id
                tabID = nil
                paneStackID = modal.paneStack.id
                closedPaneTab = modal.paneStack.panes.count > 1
                removedPane = workspaces[workspaceIndex].closePane(paneID)
            } else {
                continue
            }

            if removedPane != nil {
                updatedWorkspace = workspaces[workspaceIndex]
            }
            break
        }

        guard let removedPane,
              let updatedWorkspace,
              let workspaceID
        else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        if removedPane.isTerminal {
            try bridge.teardown(paneID: removedPane.id)
        } else if removedPane.extensionPane != nil {
            cancelMarkdownPreviewWatch(paneID: removedPane.id)
        }

        let hookName = closedPaneTab ? "pane-tab-closed" : "pane-removed"
        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: hookName,
                workspaceID: workspaceID,
                tabID: tabID,
                paneID: removedPane.id,
                sessionID: removedPane.terminalSession?.id,
                payload: .object([
                    "paneStackID": paneStackID.map { .string($0.rawValue) } ?? .null,
                ])
            )
        )

        if closedPaneTab {
            publishControlPlaneEvent(
                ControlPlaneEvent(
                    name: .paneTabClosed,
                    workspaceID: workspaceID,
                    tabID: tabID,
                    paneID: removedPane.id,
                    sessionID: removedPane.terminalSession?.id,
                    payload: .object([
                        "paneStackID": paneStackID.map { .string($0.rawValue) } ?? .null,
                    ])
                )
            )
        }

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

        if removedPane.isTerminal {
            try bridge.teardown(paneID: removedPane.id)
        } else if removedPane.extensionPane != nil {
            cancelMarkdownPreviewWatch(paneID: removedPane.id)
        }
        try hookRunner.emit(
            HookInvocation(
                category: .session,
                name: "pane-removed",
                workspaceID: updatedWorkspace.id,
                tabID: updatedWorkspace.focusedTabID,
                paneID: removedPane.id,
                sessionID: removedPane.terminalSession?.id
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
            if let focusedPaneID = workspaces[index].focusedPane?.id {
                _ = clearIdleProgressOnFocusLocked(for: focusedPaneID, workspaceIndex: index)
            }
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
        for index in workspaces.indices {
            guard workspaces[index].panes.contains(where: { $0.id == paneID }) else {
                continue
            }

            guard activeWorkspaceID != workspaces[index].id || workspaces[index].focusedPane?.id != paneID else {
                lock.unlock()
                return nil
            }

            if workspaces[index].focus(paneID: paneID) {
                setActiveWorkspaceID(workspaces[index].id)
                _ = clearIdleProgressOnFocusLocked(for: paneID, workspaceIndex: index)
                updatedWorkspace = workspaces[index]
            }
            break
        }
        lock.unlock()

        if let updatedWorkspace {
            publishPaneFocusChange(updatedWorkspace, fallbackPaneID: paneID)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func focusPaneTab(paneID: PaneID) -> Workspace? {
        focus(paneID: paneID)
    }

    @discardableResult
    public func focusNextPaneTab() -> Workspace? {
        focusActiveWorkspaceNavigation { $0.focusNextPaneTab() }
    }

    @discardableResult
    public func focusPreviousPaneTab() -> Workspace? {
        focusActiveWorkspaceNavigation { $0.focusPreviousPaneTab() }
    }

    @discardableResult
    public func focusNextPane() -> Workspace? {
        focusActiveWorkspaceNavigation { $0.focusNextPane() }
    }

    @discardableResult
    public func focusPreviousPane() -> Workspace? {
        focusActiveWorkspaceNavigation { $0.focusPreviousPane() }
    }

    @discardableResult
    public func pane(_ paneID: PaneID) -> Pane? {
        lock.lock()
        defer { lock.unlock() }
        for workspace in workspaces {
            if let pane = workspace.panes.first(where: { $0.id == paneID }) {
                return pane
            }
        }
        return nil
    }

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
    public func setPaneAlias(_ paneID: PaneID, to alias: String) throws -> Workspace? {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try clearPaneAlias(paneID)
        }

        lock.lock()
        var updatedWorkspace: Workspace?
        for workspaceIndex in workspaces.indices {
            guard let pane = workspaces[workspaceIndex].panes.first(where: { $0.id == paneID }) else {
                continue
            }
            if pane.userAlias == trimmed {
                lock.unlock()
                return nil
            }
            if workspaces[workspaceIndex].updatePane(paneID, transform: { $0.userAlias = trimmed }) {
                updatedWorkspace = workspaces[workspaceIndex]
                break
            }
        }
        lock.unlock()

        if let updatedWorkspace {
            try hookRunner.emit(
                HookInvocation(
                    category: .lifecycle,
                    name: "pane-alias-set",
                    workspaceID: updatedWorkspace.id,
                    payload: .object(["paneID": .string(paneID.rawValue), "alias": .string(trimmed)])
                )
            )
            onChange?(updatedWorkspace)
        }
        return updatedWorkspace
    }

    @discardableResult
    public func clearPaneAlias(_ paneID: PaneID) throws -> Workspace? {
        lock.lock()
        var updatedWorkspace: Workspace?
        for workspaceIndex in workspaces.indices {
            guard let pane = workspaces[workspaceIndex].panes.first(where: { $0.id == paneID }) else {
                continue
            }
            if pane.userAlias == nil {
                lock.unlock()
                return nil
            }
            if workspaces[workspaceIndex].updatePane(paneID, transform: { $0.userAlias = nil }) {
                updatedWorkspace = workspaces[workspaceIndex]
                break
            }
        }
        lock.unlock()

        if let updatedWorkspace {
            try hookRunner.emit(
                HookInvocation(
                    category: .lifecycle,
                    name: "pane-alias-cleared",
                    workspaceID: updatedWorkspace.id,
                    payload: .object(["paneID": .string(paneID.rawValue)])
                )
            )
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
        try runCommand(target: .session(sessionID), command: command) != nil
    }

    @discardableResult
    public func runCommand(
        target: ControlPlaneTerminalTarget,
        command: String
    ) throws -> ControlPlaneActionResult? {
        guard let context = resolveTerminalTarget(target) else {
            return nil
        }
        try ensureTerminalSurface(for: context.paneID)

        let cwd = workingDirectory(for: context.paneID)
        let payload: OmuxValue = .object([
            "command": .string(command),
            "cwd": cwd.map(OmuxValue.string) ?? .null,
            "outputContext": .object(["kind": .string("unavailable")]),
        ])

        lock.lock()
        commandContextBySession[context.sessionID] = CommandAutomationContext(command: command, cwd: cwd)
        lock.unlock()

        try hookRunner.emit(
            HookInvocation(
                category: .command,
                name: "command-started",
                workspaceID: context.workspaceID,
                tabID: context.tabID,
                paneID: context.paneID,
                sessionID: context.sessionID,
                payload: payload
            )
        )

        do {
            try bridge.run(command: command, inPane: context.paneID)
        } catch {
            lock.lock()
            commandContextBySession.removeValue(forKey: context.sessionID)
            lock.unlock()
            throw error
        }

        emitInputSent(
            context: context,
            text: command,
            source: "action.runCommand"
        )
        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .commandStarted,
                workspaceID: context.workspaceID,
                tabID: context.tabID,
                paneID: context.paneID,
                sessionID: context.sessionID,
                payload: payload
            )
        )
        return ControlPlaneActionResult(
            target: context,
            extra: ["command": .string(command)]
        )
    }

    @discardableResult
    public func sendText(
        target: ControlPlaneTerminalTarget,
        text: String
    ) throws -> ControlPlaneActionResult? {
        guard let context = resolveTerminalTarget(target) else {
            return nil
        }
        try ensureTerminalSurface(for: context.paneID)

        try bridge.send(text: text, toPane: context.paneID)
        emitInputSent(
            context: context,
            text: text,
            source: "action.sendText"
        )
        return ControlPlaneActionResult(
            target: context,
            extra: ["textLength": .integer(text.count)]
        )
    }

    @discardableResult
    public func setPaneStatus(
        _ request: ControlPlanePaneStatusRequest
    ) -> ControlPlaneActionResult? {
        guard let context = resolveTerminalTarget(request.target) else {
            return nil
        }

        let progress: PaneProgress?
        switch request.state {
        case .working:
            progress = PaneProgress(state: .active, value: request.value)
        case .indeterminate:
            progress = PaneProgress(state: .indeterminate, value: request.value)
        case .error:
            progress = PaneProgress(state: .error, value: request.value)
        case .needsInput:
            progress = PaneProgress(state: .needsInput, value: request.value)
        case .idle:
            progress = PaneProgress(state: .paused, value: request.value)
        case .clear:
            progress = nil
        }

        var updatedWorkspace: Workspace?
        lock.lock()
        for workspaceIndex in workspaces.indices {
            guard workspaces[workspaceIndex].tabs.contains(where: { $0.panes.contains(where: { $0.id == context.paneID }) }) else {
                continue
            }

            _ = workspaces[workspaceIndex].updatePane(context.paneID) { pane in
                pane.terminalState.progress = progress
                if request.state == .clear {
                    pane.terminalState.agentStatusAdapterID = nil
                }
            }

            if request.state == .idle {
                handleIdleProgressSetLocked(for: context.paneID, workspaceIndex: workspaceIndex)
            } else {
                progressIdleClearTokens.removeValue(forKey: context.paneID)
            }

            updatedWorkspace = workspaces[workspaceIndex]
            break
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        let source = request.source ?? "pane.status"
        let payload = paneStatusPayload(
            state: request.state,
            value: request.value,
            label: request.label,
            message: request.message,
            source: source
        )

        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .paneStatusChanged,
                workspaceID: context.workspaceID,
                tabID: context.tabID,
                paneID: context.paneID,
                sessionID: context.sessionID,
                payload: payload
            )
        )

        return ControlPlaneActionResult(
            target: context,
            extra: [
                "status": RPCValue(payload),
            ]
        )
    }

    public func handleInput(_ event: NormalizedKeyEvent, in paneID: PaneID) throws {
        try ensureTerminalSurface(for: paneID)
        try bridge.handle(event, inPane: paneID)
    }

    public func paste(_ text: String, in paneID: PaneID) throws {
        try ensureTerminalSurface(for: paneID)
        try bridge.send(text: text, toPane: paneID)
    }

    public func resize(paneID: PaneID, columns: Int, rows: Int) throws {
        try ensureTerminalSurface(for: paneID)
        try bridge.resize(paneID: paneID, columns: columns, rows: rows)
    }

    @discardableResult
    public func updateSplitProportions(
        _ proportions: [Double],
        forChildPaneIDs childPaneIDs: [PaneID]
    ) -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let index = activeWorkspaceIndex,
           workspaces[index].updateSplitProportions(proportions, forChildPaneIDs: childPaneIDs) {
            updatedWorkspace = workspaces[index]
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func equalizeSplits() -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let index = activeWorkspaceIndex,
           workspaces[index].equalizeSplitsInFocusedTab() {
            updatedWorkspace = workspaces[index]
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func resizeSplit(_ direction: PaneSplitResizeDirection) -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let index = activeWorkspaceIndex,
           workspaces[index].resizeFocusedSplit(direction) {
            updatedWorkspace = workspaces[index]
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    public func focusedPaneID(in workspace: Workspace) -> PaneID? {
        workspace.focusedPane?.id
    }

    @discardableResult
    public func moveWorkspace(_ workspaceID: WorkspaceID, toDisplayIndex targetIndex: Int) -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let sourceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
           workspaces.indices.contains(targetIndex),
           sourceIndex != targetIndex {
            let workspace = workspaces.remove(at: sourceIndex)
            workspaces.insert(workspace, at: targetIndex)
            updatedWorkspace = activeWorkspaceID.flatMap { activeID in
                workspaces.first(where: { $0.id == activeID })
            } ?? workspace
        }
        lock.unlock()

        if let updatedWorkspace {
            onChange?(updatedWorkspace)
        }

        return updatedWorkspace
    }

    @discardableResult
    public func moveActiveWorkspaceUp() -> Workspace? {
        lock.lock()
        guard let activeWorkspaceID, let activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }
        lock.unlock()
        return moveWorkspace(activeWorkspaceID, toDisplayIndex: activeWorkspaceIndex - 1)
    }

    @discardableResult
    public func moveActiveWorkspaceDown() -> Workspace? {
        lock.lock()
        guard let activeWorkspaceID, let activeWorkspaceIndex else {
            lock.unlock()
            return nil
        }
        lock.unlock()
        return moveWorkspace(activeWorkspaceID, toDisplayIndex: activeWorkspaceIndex + 1)
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

    private func focusActiveWorkspace(_ transform: (inout Workspace) -> Bool) -> Workspace? {
        var updatedWorkspace: Workspace?
        lock.lock()
        if let index = activeWorkspaceIndex, transform(&workspaces[index]) {
            if let focusedPaneID = workspaces[index].focusedPane?.id {
                _ = clearIdleProgressOnFocusLocked(for: focusedPaneID, workspaceIndex: index)
            }
            updatedWorkspace = workspaces[index]
        }
        lock.unlock()
        return updatedWorkspace
    }

    private func focusActiveWorkspaceNavigation(_ transform: (inout Workspace) -> Bool) -> Workspace? {
        let updatedWorkspace = focusActiveWorkspace(transform)
        if let updatedWorkspace {
            publishPaneFocusChange(updatedWorkspace)
        }
        return updatedWorkspace
    }

    private func publishPaneFocusChange(_ workspace: Workspace, fallbackPaneID: PaneID? = nil) {
        let focusedPane = workspace.focusedPane
        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .paneTabFocused,
                workspaceID: workspace.id,
                tabID: workspace.focusedTabID,
                paneID: focusedPane?.id ?? fallbackPaneID,
                sessionID: focusedPane?.terminalSession?.id,
                payload: .object([:])
            )
        )
        onChange?(workspace)
    }

    private func rebuildLookupIndexesLocked() {
        workspaceIndexByID.removeAll(keepingCapacity: true)
        tabLocationByID.removeAll(keepingCapacity: true)
        paneLocationByID.removeAll(keepingCapacity: true)
        sessionLocationByID.removeAll(keepingCapacity: true)

        for (workspaceIndex, workspace) in workspaces.enumerated() {
            workspaceIndexByID[workspace.id] = workspaceIndex
            for (tabIndex, tab) in workspace.tabs.enumerated() {
                tabLocationByID[tab.id] = (workspaceIndex: workspaceIndex, tabIndex: tabIndex)
                for (paneIndex, pane) in tab.panes.enumerated() {
                    let location = WorkspaceLookupLocation(
                        workspaceIndex: workspaceIndex,
                        tabIndex: tabIndex,
                        floatingPaneModalIndex: nil,
                        paneIndex: paneIndex
                    )
                    paneLocationByID[pane.id] = location
                    if let sessionID = pane.terminalSession?.id {
                        sessionLocationByID[sessionID] = location
                    }
                }
            }
            for (modalIndex, modal) in workspace.floatingPaneModals.enumerated() {
                for (paneIndex, pane) in modal.paneStack.panes.enumerated() {
                    let location = WorkspaceLookupLocation(
                        workspaceIndex: workspaceIndex,
                        tabIndex: nil,
                        floatingPaneModalIndex: modalIndex,
                        paneIndex: paneIndex
                    )
                    paneLocationByID[pane.id] = location
                    if let sessionID = pane.terminalSession?.id {
                        sessionLocationByID[sessionID] = location
                    }
                }
            }
        }
        lookupIndexesDirty = false
    }

    private func ensureLookupIndexesLocked() {
        guard lookupIndexesDirty else {
            return
        }
        rebuildLookupIndexesLocked()
    }

    private func workspacePaneLocked(
        at location: WorkspaceLookupLocation
    ) -> WorkspacePaneResolution? {
        guard workspaces.indices.contains(location.workspaceIndex) else {
            return nil
        }
        let workspace = workspaces[location.workspaceIndex]
        if let tabIndex = location.tabIndex {
            guard workspace.tabs.indices.contains(tabIndex) else {
                return nil
            }
            let tab = workspace.tabs[tabIndex]
            guard tab.panes.indices.contains(location.paneIndex) else {
                return nil
            }
            let pane = tab.panes[location.paneIndex]
            return WorkspacePaneResolution(workspace: workspace, tab: tab, floatingPaneModal: nil, pane: pane)
        }
        if let floatingPaneModalIndex = location.floatingPaneModalIndex {
            guard workspace.floatingPaneModals.indices.contains(floatingPaneModalIndex) else {
                return nil
            }
            let modal = workspace.floatingPaneModals[floatingPaneModalIndex]
            guard modal.paneStack.panes.indices.contains(location.paneIndex) else {
                return nil
            }
            let pane = modal.paneStack.panes[location.paneIndex]
            return WorkspacePaneResolution(workspace: workspace, tab: nil, floatingPaneModal: modal, pane: pane)
        }
        return nil
    }

    private func paneLocationLocked(for paneID: PaneID) -> WorkspaceLookupLocation? {
        ensureLookupIndexesLocked()
        guard let location = paneLocationByID[paneID],
              workspacePaneLocked(at: location)?.pane.id == paneID
        else {
            lookupIndexesDirty = true
            ensureLookupIndexesLocked()
            guard let rebuilt = paneLocationByID[paneID],
                  workspacePaneLocked(at: rebuilt)?.pane.id == paneID
            else {
                return nil
            }
            return rebuilt
        }
        return location
    }

    private func sessionLocationLocked(for sessionID: SessionID) -> WorkspaceLookupLocation? {
        ensureLookupIndexesLocked()
        guard let location = sessionLocationByID[sessionID],
              workspacePaneLocked(at: location)?.pane.terminalSession?.id == sessionID
        else {
            lookupIndexesDirty = true
            ensureLookupIndexesLocked()
            guard let rebuilt = sessionLocationByID[sessionID],
                  workspacePaneLocked(at: rebuilt)?.pane.terminalSession?.id == sessionID
            else {
                return nil
            }
            return rebuilt
        }
        return location
    }

    private func workspaceIndexLocked(for workspaceID: WorkspaceID) -> Int? {
        ensureLookupIndexesLocked()
        guard let index = workspaceIndexByID[workspaceID], workspaces.indices.contains(index) else {
            lookupIndexesDirty = true
            ensureLookupIndexesLocked()
            guard let rebuilt = workspaceIndexByID[workspaceID], workspaces.indices.contains(rebuilt) else {
                return nil
            }
            return rebuilt
        }
        return index
    }

    private func tabLocationLocked(for tabID: TabID) -> (workspaceIndex: Int, tabIndex: Int)? {
        ensureLookupIndexesLocked()
        guard let location = tabLocationByID[tabID],
              workspaces.indices.contains(location.workspaceIndex),
              workspaces[location.workspaceIndex].tabs.indices.contains(location.tabIndex),
              workspaces[location.workspaceIndex].tabs[location.tabIndex].id == tabID
        else {
            lookupIndexesDirty = true
            ensureLookupIndexesLocked()
            guard let rebuilt = tabLocationByID[tabID],
                  workspaces.indices.contains(rebuilt.workspaceIndex),
                  workspaces[rebuilt.workspaceIndex].tabs.indices.contains(rebuilt.tabIndex),
                  workspaces[rebuilt.workspaceIndex].tabs[rebuilt.tabIndex].id == tabID
            else {
                return nil
            }
            return rebuilt
        }
        return location
    }

    private var activeWorkspaceIndex: Int? {
        // Lock must be held by caller.
        guard let activeWorkspaceID else {
            return nil
        }
        return workspaceIndexLocked(for: activeWorkspaceID)
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
        guard let location = sessionLocationLocked(for: sessionID) else {
            return nil
        }
        return workspacePaneLocked(at: location)?.pane
    }

    private func controlPlaneContext(
        for sessionID: SessionID
    ) -> (workspaceID: WorkspaceID, tabID: TabID?, paneID: PaneID)? {
        lock.lock()
        defer { lock.unlock() }
        guard let location = sessionLocationLocked(for: sessionID),
              let resolved = workspacePaneLocked(at: location)
        else {
            return nil
        }
        return (workspaceID: resolved.workspace.id, tabID: resolved.tab?.id, paneID: resolved.pane.id)
    }

    private func resolveTerminalTargetLocked(_ target: ControlPlaneTerminalTarget) -> ControlPlaneTerminalContext? {
        switch target {
        case .session(let sessionID):
            guard let location = sessionLocationLocked(for: sessionID),
                  let resolved = workspacePaneLocked(at: location)
            else {
                return nil
            }
            return terminalContext(
                workspace: resolved.workspace,
                tabID: resolved.tab?.id,
                paneStackID: resolved.tab?.rootLayout.paneStack(containingPaneID: resolved.pane.id)?.id ?? resolved.floatingPaneModal?.paneStack.id,
                pane: resolved.pane
            )
        case .pane(let paneID):
            guard let location = paneLocationLocked(for: paneID),
                  let resolved = workspacePaneLocked(at: location)
            else {
                return nil
            }
            return terminalContext(
                workspace: resolved.workspace,
                tabID: resolved.tab?.id,
                paneStackID: resolved.tab?.rootLayout.paneStack(containingPaneID: resolved.pane.id)?.id ?? resolved.floatingPaneModal?.paneStack.id,
                pane: resolved.pane
            )
        case .tab(let tabID):
            guard let location = tabLocationLocked(for: tabID) else {
                return nil
            }
            let workspace = workspaces[location.workspaceIndex]
            let tab = workspace.tabs[location.tabIndex]
            guard let pane = tab.focusedPane else {
                return nil
            }
            return terminalContext(workspace: workspace, tab: tab, pane: pane)
        case .workspace(let workspaceID):
            guard let workspaceIndex = workspaceIndexLocked(for: workspaceID) else {
                return nil
            }
            let workspace = workspaces[workspaceIndex]
            guard let pane = workspace.focusedPane
            else {
                return nil
            }
            return terminalContext(
                workspace: workspace,
                tabID: workspace.focusedFloatingPaneModalID == nil ? workspace.focusedTabID : nil,
                paneStackID: paneStackID(for: pane.id, in: workspace),
                pane: pane
            )
        case .focused:
            guard let activeWorkspaceIndex,
                  workspaces.indices.contains(activeWorkspaceIndex)
            else {
                return nil
            }
            let workspace = workspaces[activeWorkspaceIndex]
            guard let pane = workspace.focusedPane
            else {
                return nil
            }
            return terminalContext(
                workspace: workspace,
                tabID: workspace.focusedFloatingPaneModalID == nil ? workspace.focusedTabID : nil,
                paneStackID: paneStackID(for: pane.id, in: workspace),
                pane: pane
            )
        }
    }

    private func historyClearPaneIDsLocked(target: ControlPlaneTerminalTarget?) -> [PaneID]? {
        guard let target else {
            return workspaces.flatMap { $0.panes.filter(\.isTerminal).map(\.id) }
        }

        switch target {
        case .session, .pane, .focused:
            return resolveTerminalTargetLocked(target).map { [$0.paneID] }
        case .tab(let tabID):
            guard let location = tabLocationLocked(for: tabID) else {
                return nil
            }
            let workspace = workspaces[location.workspaceIndex]
            let tab = workspace.tabs[location.tabIndex]
            return tab.panes.filter(\.isTerminal).map(\.id)
        case .workspace(let workspaceID):
            guard let workspaceIndex = workspaceIndexLocked(for: workspaceID) else {
                return nil
            }
            let workspace = workspaces[workspaceIndex]
            return workspace.panes.filter(\.isTerminal).map(\.id)
        }
    }

    private func terminalContext(workspace: Workspace, tab: Tab, pane: Pane) -> ControlPlaneTerminalContext? {
        terminalContext(
            workspace: workspace,
            tabID: tab.id,
            paneStackID: tab.rootLayout.paneStack(containingPaneID: pane.id)?.id,
            pane: pane
        )
    }

    private func terminalContext(
        workspace: Workspace,
        tabID: TabID?,
        paneStackID: PaneStackID?,
        pane: Pane
    ) -> ControlPlaneTerminalContext? {
        guard let session = pane.terminalSession else {
            return nil
        }
        return ControlPlaneTerminalContext(
            workspaceID: workspace.id,
            tabID: tabID,
            paneStackID: paneStackID,
            paneID: pane.id,
            sessionID: session.id
        )
    }

    private func terminalContext(for paneID: PaneID) -> ControlPlaneTerminalContext? {
        lock.lock()
        defer { lock.unlock() }
        guard let location = paneLocationLocked(for: paneID),
              let resolved = workspacePaneLocked(at: location)
        else {
            return nil
        }
        return terminalContext(
            workspace: resolved.workspace,
            tabID: resolved.tab?.id,
            paneStackID: resolved.tab?.rootLayout.paneStack(containingPaneID: resolved.pane.id)?.id ?? resolved.floatingPaneModal?.paneStack.id,
            pane: resolved.pane
        )
    }

    private static func historyTargets(in workspace: Workspace) -> [PaneHistoryTarget] {
        workspace.tabs.flatMap { tab in
            tab.panes.compactMap { pane in
                guard let session = pane.terminalSession else {
                    return nil
                }
                return PaneHistoryTarget(
                    workspaceID: workspace.id,
                    workspaceName: workspace.name,
                    tabID: tab.id,
                    tabTitle: tab.title,
                    paneStackID: tab.rootLayout.paneStack(containingPaneID: pane.id)?.id,
                    paneID: pane.id,
                    paneTitle: pane.title,
                    sessionID: session.id,
                    workingDirectory: pane.terminalState.reportedWorkingDirectory ?? session.workingDirectory,
                    persistedHistory: pane.terminalState.restoredScrollback
                )
            }
        } + workspace.floatingPaneModals.flatMap { modal in
            modal.paneStack.panes.compactMap { pane in
                guard let session = pane.terminalSession else {
                    return nil
                }
                guard let fallbackTab = workspace.focusedTab ?? workspace.tabs.first else {
                    return nil
                }
                return PaneHistoryTarget(
                    workspaceID: workspace.id,
                    workspaceName: workspace.name,
                    tabID: fallbackTab.id,
                    tabTitle: fallbackTab.title,
                    paneStackID: modal.paneStack.id,
                    paneID: pane.id,
                    paneTitle: pane.title,
                    sessionID: session.id,
                    workingDirectory: pane.terminalState.reportedWorkingDirectory ?? session.workingDirectory,
                    persistedHistory: pane.terminalState.restoredScrollback
                )
            }
        }
    }

    private static func historyTarget(paneID: PaneID, in workspace: Workspace) -> PaneHistoryTarget? {
        historyTargets(in: workspace).first(where: { $0.paneID == paneID })
    }

    private func workingDirectory(for paneID: PaneID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let location = paneLocationLocked(for: paneID),
              let pane = workspacePaneLocked(at: location)?.pane
        else {
            return nil
        }
        return Self.terminalWorkingDirectory(for: pane)
    }

    private static func terminalWorkingDirectory(for pane: Pane) -> String? {
        let path = pane.terminalState.reportedWorkingDirectory ?? pane.terminalSession?.workingDirectory
        return path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func normalizedDirectoryPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    private func terminalTextActivationContext(
        for request: TerminalTextActivationRequest,
        hit: TerminalTextActivationHit
    ) -> TerminalTextActivationContext {
        let cwd = workingDirectory(for: request.paneID)
        return TerminalTextActivationContext(
            request: request,
            hit: hit,
            cwd: cwd,
            resolvedPath: TerminalTextActivationResolver.resolvedLocalPath(token: hit.token, cwd: cwd)
        )
    }

    private func emitTerminalTextActivationHook(_ context: TerminalTextActivationContext) {
        let terminalContext = terminalContext(for: context.request.paneID)
        do {
            try hookRunner.emit(
                HookInvocation(
                    category: .input,
                    name: "terminal-text-activated",
                    workspaceID: terminalContext?.workspaceID,
                    tabID: terminalContext?.tabID,
                    paneID: context.request.paneID,
                    sessionID: terminalContext?.sessionID,
                    payload: terminalTextActivationPayload(context)
                )
            )
        } catch {
            fputs("warning: failed to emit terminal-text-activated hook: \(error)\n", stderr)
        }
    }

    private func publishTerminalTextActivationEvent(_ context: TerminalTextActivationContext) {
        let terminalContext = terminalContext(for: context.request.paneID)
        publishControlPlaneEvent(
            ControlPlaneEvent(
                name: .textActivated,
                workspaceID: terminalContext?.workspaceID,
                tabID: terminalContext?.tabID,
                paneID: context.request.paneID,
                sessionID: terminalContext?.sessionID,
                payload: terminalTextActivationPayload(context)
            )
        )
    }

    private func terminalTextActivationPayload(_ context: TerminalTextActivationContext) -> OmuxValue {
        .object([
            "token": .string(context.hit.token),
            "row": .integer(context.hit.row),
            "column": .integer(context.hit.column),
            "cwd": context.cwd.map(OmuxValue.string) ?? .null,
            "resolvedPath": context.resolvedPath.map(OmuxValue.string) ?? .null,
            "modifiers": .integer(Int(context.request.modifiers.rawValue)),
        ])
    }

    private func shouldOpenMarkdownPreview(for path: String) -> Bool {
        lock.lock()
        let markdownPreviewConfiguration = self.markdownPreviewConfiguration
        lock.unlock()

        guard markdownPreviewConfiguration.enabled else {
            return false
        }

        let fileURL = URL(fileURLWithPath: path)
        let fileExtension = fileURL.pathExtension.lowercased()
        guard fileExtension == "md" || fileExtension == "markdown" else {
            return false
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue == false
            && FileManager.default.isReadableFile(atPath: path)
    }

    private func openMarkdownPreview(for path: String) {
        let fileURL = URL(fileURLWithPath: path)
        let markdownPreviewConfiguration = markdownPreviewConfigurationSnapshot()
        let markdown: String
        do {
            markdown = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            let presentationStyle = ExtensionPanePresentationStyle(rawValue: markdownPreviewConfiguration.presentation) ?? .paneTab
            let descriptor = ExtensionPaneDescriptor(
                pluginID: OmuxMarkdownPreviewPlugin.pluginID,
                contentKind: .html,
                source: path,
                html: "",
                status: .error,
                message: "Unable to render \(fileURL.lastPathComponent): \(error.localizedDescription)",
                presentationStyle: presentationStyle
            )
            if let paneID = markdownPreviewPaneID(for: path) {
                _ = updateExtensionPane(paneID: paneID, descriptor: descriptor, title: fileURL.lastPathComponent)
            } else {
                _ = createExtensionPane(title: fileURL.lastPathComponent, descriptor: descriptor)
            }
            return
        }

        let descriptor = markdownPreviewDescriptor(
            markdown: markdown,
            fileURL: fileURL,
            theme: markdownPreviewConfiguration.theme,
            presentation: markdownPreviewConfiguration.presentation
        )
        var paneID = markdownPreviewPaneID(for: path)
        if let paneID {
            _ = updateExtensionPane(paneID: paneID, descriptor: descriptor, title: fileURL.lastPathComponent)
        } else {
            paneID = createExtensionPane(title: fileURL.lastPathComponent, descriptor: descriptor)?.pane.id
        }

        if let paneID {
            startMarkdownPreviewWatch(paneID: paneID, sourcePath: path, initialMarkdown: markdown)
        }
    }

    private func markdownPreviewConfigurationSnapshot() -> OmuxConfigPlugins.MarkdownPreview {
        lock.lock()
        defer { lock.unlock() }
        return markdownPreviewConfiguration
    }

    private func markdownPreviewDescriptor(markdown: String, fileURL: URL, theme: String, presentation: String) -> ExtensionPaneDescriptor {
        let presentationStyle = ExtensionPanePresentationStyle(rawValue: presentation) ?? .paneTab
        do {
            let html = try OmuxMarkdownPreviewRenderer(theme: theme).render(
                markdown: markdown,
                title: fileURL.lastPathComponent,
                sourcePath: fileURL.path
            )
            return ExtensionPaneDescriptor(
                pluginID: OmuxMarkdownPreviewPlugin.pluginID,
                contentKind: .html,
                source: fileURL.path,
                html: html,
                status: .ready,
                presentationStyle: presentationStyle
            )
        } catch {
            return ExtensionPaneDescriptor(
                pluginID: OmuxMarkdownPreviewPlugin.pluginID,
                contentKind: .html,
                source: fileURL.path,
                html: "",
                status: .error,
                message: "Unable to render \(fileURL.lastPathComponent): \(error.localizedDescription)",
                presentationStyle: presentationStyle
            )
        }
    }

    private func startMarkdownPreviewWatch(paneID: PaneID, sourcePath: String, initialMarkdown: String) {
        let token = UUID()
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let task = Task { [weak self] in
            defer {
                self?.finishMarkdownPreviewWatch(paneID: paneID, token: token)
            }

            var lastRenderedMarkdown = initialMarkdown
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: 400_000_000)
                } catch {
                    return
                }

                guard Task.isCancelled == false else {
                    return
                }
                guard let self else {
                    return
                }
                guard self.isMarkdownPreviewPane(paneID, displaying: sourcePath) else {
                    return
                }
                guard let markdown = try? String(contentsOf: sourceURL, encoding: .utf8) else {
                    continue
                }
                guard markdown != lastRenderedMarkdown else {
                    continue
                }
                lastRenderedMarkdown = markdown
                let updated = await MainActor.run { [weak self] in
                    guard let self else {
                        return false
                    }
                    return self.updateMarkdownPreview(paneID: paneID, sourceURL: sourceURL, markdown: markdown)
                }
                guard updated else {
                    return
                }
            }
        }

        lock.lock()
        markdownPreviewWatchTasks[paneID]?.task.cancel()
        markdownPreviewWatchTasks[paneID] = (token: token, task: task)
        lock.unlock()
    }

    private func updateMarkdownPreview(paneID: PaneID, sourceURL: URL, markdown: String) -> Bool {
        let markdownPreviewConfiguration = markdownPreviewConfigurationSnapshot()
        let descriptor = markdownPreviewDescriptor(
            markdown: markdown,
            fileURL: sourceURL,
            theme: markdownPreviewConfiguration.theme,
            presentation: markdownPreviewConfiguration.presentation
        )
        return updateExtensionPane(paneID: paneID, descriptor: descriptor, title: sourceURL.lastPathComponent) != nil
    }

    private func finishMarkdownPreviewWatch(paneID: PaneID, token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = markdownPreviewWatchTasks[paneID],
              entry.token == token
        else {
            return
        }
        markdownPreviewWatchTasks.removeValue(forKey: paneID)
    }

    private func cancelMarkdownPreviewWatch(paneID: PaneID) {
        lock.lock()
        let entry = markdownPreviewWatchTasks.removeValue(forKey: paneID)
        lock.unlock()
        entry?.task.cancel()
    }

    private func isMarkdownPreviewPane(_ paneID: PaneID, displaying sourcePath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return workspaces.contains { workspace in
            workspace.panes.contains { pane in
                pane.id == paneID
                    && pane.extensionPane?.pluginID == OmuxMarkdownPreviewPlugin.pluginID
                    && pane.extensionPane?.source == sourcePath
            }
        }
    }

    private func markdownPreviewPaneID(for sourcePath: String) -> PaneID? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeWorkspaceIndex else {
            return nil
        }

        return workspaces[activeWorkspaceIndex]
            .panes
            .first { pane in
                pane.extensionPane?.pluginID == OmuxMarkdownPreviewPlugin.pluginID
                    && pane.extensionPane?.source == sourcePath
            }?
            .id
    }

    func enrichedCommandCompletionPayload(
        for event: TerminalActionEvent,
        context: ControlPlaneTerminalContext
    ) -> OmuxValue {
        guard case .commandFinished = event.action else {
            return event.payload
        }

        var object = event.payload.objectValue ?? [:]

        lock.lock()
        let commandContext = commandContextBySession.removeValue(forKey: context.sessionID)
        lock.unlock()

        object["command"] = commandContext.map { .string($0.command) } ?? .null
        if let cwd = commandContext?.cwd ?? workingDirectory(for: context.paneID) {
            object["cwd"] = .string(cwd)
        } else {
            object["cwd"] = .null
        }
        object["outputContext"] = outputContext(for: context.paneID)
        return .object(object)
    }

    private func outputContext(for paneID: PaneID) -> OmuxValue {
        let snapshot = bridge.terminalTextSnapshot(for: paneID, maxBytes: 4_000, maxLines: PaneScrollbackSnapshot.defaultMaxLines)
        guard snapshot.isAvailable else {
            return .object([
                "kind": .string("unavailable"),
                "reason": snapshot.unavailableReason.map(OmuxValue.string) ?? .null,
            ])
        }

        return .object([
            "kind": .string("tail"),
            "tail": .string(snapshot.text),
            "truncated": .bool(snapshot.truncated),
        ])
    }

    private func paneStackID(for paneID: PaneID, in workspace: Workspace) -> PaneStackID? {
        workspace.tabs
            .compactMap { $0.rootLayout.paneStack(containingPaneID: paneID)?.id }
            .first
        ?? workspace.floatingPaneModals.first(where: { $0.paneStack.panes.contains(where: { $0.id == paneID }) })?.paneStack.id
    }

    private func floatingPaneModalID(for paneID: PaneID, in workspace: Workspace) -> FloatingPaneModalID? {
        workspace.floatingPaneModals
            .first(where: { $0.paneStack.panes.contains(where: { $0.id == paneID }) })?
            .id
    }

    private func dockedTargetPaneStackID(in workspace: Workspace) -> PaneStackID? {
        if let focusedStackID = workspace.tabs
            .first(where: { $0.id == workspace.focusedTabID })?
            .focusedPaneStack?.id {
            return focusedStackID
        }

        return workspace.tabs
            .compactMap { $0.focusedPaneStack?.id }
            .first
    }

    private func paneStack(id paneStackID: PaneStackID, in workspace: Workspace) -> PaneStack? {
        workspace.tabs
            .compactMap { $0.rootLayout.paneStack(id: paneStackID) }
            .first
        ?? workspace.floatingPaneModals.first(where: { $0.paneStack.id == paneStackID })?.paneStack
    }

    func terminalActionCoordinatorHandle(_ event: TerminalActionEvent) {
        terminalActionCoordinator.handle(event)
    }

    private func emitInputSent(
        context: ControlPlaneTerminalContext,
        text: String?,
        key: String? = nil,
        keyCode: UInt16? = nil,
        modifiers: KeyModifiers = [],
        route: NormalizedInputRoute? = nil,
        source: String
    ) {
        guard let surface = bridge.surface(for: context.paneID) else {
            return
        }

        terminalActionCoordinatorHandle(
            TerminalActionEvent(
                paneID: context.paneID,
                sessionID: context.sessionID,
                runtimeSurfaceID: surface.runtimeSurfaceID,
                action: .inputSent(
                    text: text,
                    key: key,
                    keyCode: keyCode,
                    modifiers: modifiers,
                    route: route,
                    source: source
                )
            )
        )
    }

    func publishControlPlaneEvent(_ event: ControlPlaneEvent) {
        controlPlaneEventHandler?(event)
    }

    func publishTerminalEvent(_ event: ControlPlaneEvent) {
        publishControlPlaneEvent(event)
    }

    func deliverNotification(_ request: NotificationRequest) {
        lock.lock()
        lastNotification = request
        lock.unlock()

        DispatchQueue.main.async {
            NSApplication.shared.requestUserAttention(.informationalRequest)
        }
    }

    func applyTerminalActionState(_ event: TerminalActionEvent) -> ControlPlaneTerminalContext? {
        var updatedWorkspace: Workspace?
        var context: ControlPlaneTerminalContext?
        var shouldScheduleTrailingTitleUpdate = false

        lock.lock()
        guard let location = paneLocationLocked(for: event.paneID),
              let resolved = workspacePaneLocked(at: location)
        else {
            lock.unlock()
            return nil
        }
        let workspaceIndex = location.workspaceIndex
        let paneStackID = resolved.tab?.rootLayout.paneStack(containingPaneID: event.paneID)?.id
            ?? resolved.floatingPaneModal?.paneStack.id
        context = ControlPlaneTerminalContext(
            workspaceID: resolved.workspace.id,
            tabID: resolved.tab?.id,
            paneStackID: paneStackID,
            paneID: event.paneID,
            sessionID: event.sessionID
        )

        switch event.action {
        case .workingDirectoryChanged(let path):
            var didChange = false
            _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                if var session = pane.terminalSession {
                    if session.workingDirectory != path {
                        session.workingDirectory = path
                        pane.terminalSession = session
                        didChange = true
                    }
                }
                if pane.terminalState.reportedWorkingDirectory != path {
                    pane.terminalState.reportedWorkingDirectory = path
                    didChange = true
                }
            }
            if didChange {
                updatedWorkspace = workspaces[workspaceIndex]
            }
        case .titleChanged(let title):
            var shouldUpdateWorkspace = false
            var shouldHandleAIStatusIdle = false
            let displayTitle = Self.displayTitle(forReportedTerminalTitle: title)
            _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                if pane.terminalState.reportedTitle != title {
                    pane.terminalState.reportedTitle = title
                }
                if applyAIStatusTitleObservationLocked(
                    title: title,
                    paneID: event.paneID,
                    workspaceIndex: workspaceIndex,
                    pane: &pane,
                    shouldHandleIdle: &shouldHandleAIStatusIdle
                ) {
                    shouldUpdateWorkspace = true
                }
                guard let displayTitle,
                      deliveredTerminalDisplayTitleByPane[event.paneID] != displayTitle
                else {
                    return
                }

                if shouldApplyTerminalDisplayTitleUpdateLocked(for: event.paneID, at: Date()) {
                    // When a user alias is set, store the title internally but do not
                    // promote it to pane.title (which drives the tab display).
                    if pane.userAlias == nil,
                       Self.shouldPromoteTerminalDisplayTitleToPaneTitle(displayTitle) {
                        if pane.title != displayTitle {
                            pane.title = displayTitle
                        }
                        deliveredTerminalDisplayTitleByPane[event.paneID] = displayTitle
                        lastTerminalDisplayTitleUpdateByPane[event.paneID] = Date()
                        shouldUpdateWorkspace = true
                    }
                } else {
                    pendingTerminalDisplayTitlePaneIDs.insert(event.paneID)
                    shouldScheduleTrailingTitleUpdate = true
                }
            }
            if shouldHandleAIStatusIdle {
                handleIdleProgressSetLocked(for: event.paneID, workspaceIndex: workspaceIndex)
                shouldUpdateWorkspace = true
            }
            if shouldUpdateWorkspace {
                updatedWorkspace = workspaces[workspaceIndex]
            }
        case .tabTitleChanged(let title):
            if let tabIndex = location.tabIndex,
               workspaces[workspaceIndex].tabs[tabIndex].title != title {
                workspaces[workspaceIndex].tabs[tabIndex].title = title
                updatedWorkspace = workspaces[workspaceIndex]
            }
        case .progressReported(let state, let progress):
            var didChange = false
            _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                let previousAgentStatusAdapterID = pane.terminalState.agentStatusAdapterID
                let nextProgress: PaneProgress
                switch state {
                case .removed:
                    nextProgress = PaneProgress(state: .paused)
                    pane.terminalState.agentStatusAdapterID = nil
                case .active:
                    progressIdleClearTokens.removeValue(forKey: event.paneID)
                    nextProgress = PaneProgress(state: .active, value: progress)
                case .error:
                    progressIdleClearTokens.removeValue(forKey: event.paneID)
                    nextProgress = PaneProgress(state: .error, value: progress)
                case .indeterminate:
                    progressIdleClearTokens.removeValue(forKey: event.paneID)
                    nextProgress = PaneProgress(state: .indeterminate, value: progress)
                case .paused:
                    progressIdleClearTokens.removeValue(forKey: event.paneID)
                    nextProgress = PaneProgress(state: .paused, value: progress)
                }
                if pane.terminalState.progress != nextProgress {
                    pane.terminalState.progress = nextProgress
                    didChange = true
                }
                if pane.terminalState.agentStatusAdapterID != previousAgentStatusAdapterID {
                    didChange = true
                }
            }
            if didChange, state == .removed {
                handleIdleProgressSetLocked(for: event.paneID, workspaceIndex: workspaceIndex)
            }
            if didChange {
                updatedWorkspace = workspaces[workspaceIndex]
            }
        case .childExited(let exitCode, let elapsedMilliseconds):
            var didChange = false
            let nextExit = PaneExitStatus(
                exitCode: exitCode,
                elapsedMilliseconds: elapsedMilliseconds
            )
            _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                if pane.terminalState.lastExit != nextExit {
                    pane.terminalState.lastExit = nextExit
                    didChange = true
                }
            }
            if didChange {
                updatedWorkspace = workspaces[workspaceIndex]
            }
        case .rendererHealthChanged(let isHealthy):
            var didChange = false
            _ = workspaces[workspaceIndex].updatePane(event.paneID) { pane in
                if pane.terminalState.rendererHealthy != isHealthy {
                    pane.terminalState.rendererHealthy = isHealthy
                    didChange = true
                }
            }
            if didChange {
                updatedWorkspace = workspaces[workspaceIndex]
            }
        case .openURL, .desktopNotification, .bell, .inputSent, .commandFinished, .searchMatchesUpdated:
            break
        }

        lock.unlock()
        if shouldScheduleTrailingTitleUpdate {
            scheduleTerminalDisplayTitleUpdate()
        }
        if let updatedWorkspace {
            scheduleTerminalStateChangeUpdate(for: updatedWorkspace.id)
        }
        return context
    }

    private func scheduleTerminalStateChangeUpdate(for workspaceID: WorkspaceID) {
        lock.lock()
        pendingTerminalStateWorkspaceIDs.insert(workspaceID)
        guard terminalStateChangeUpdateScheduled == false else {
            lock.unlock()
            return
        }
        terminalStateChangeUpdateScheduled = true
        let delay = terminalStateChangeCoalescingDelay
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.flushTerminalStateChangeUpdates()
        }
    }

    private static func displayTitle(forReportedTerminalTitle title: String) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            return nil
        }

        let strippedTitle = String(trimmedTitle.drop { character in
            character.isWhitespace || character.isTerminalTitleSpinnerGlyph
        })
        let displayTitle = strippedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayTitle.isEmpty ? trimmedTitle : displayTitle
    }

    private func shouldApplyTerminalDisplayTitleUpdateLocked(for paneID: PaneID, at date: Date) -> Bool {
        guard let lastUpdate = lastTerminalDisplayTitleUpdateByPane[paneID] else {
            return true
        }

        return date.timeIntervalSince(lastUpdate) >= terminalDisplayTitleUpdateMinimumInterval
    }

    private static func shouldPromoteTerminalDisplayTitleToPaneTitle(_ title: String) -> Bool {
        if WorkspaceIconResolver.terminalApplicationIcon(forTitle: title) == nil {
            return true
        }

        let lowercased = title.localizedLowercase
        let aiTerms = ["copilot", "github copilot", "claude", "chatgpt", "openai", "codex"]
        return aiTerms.contains { lowercased.contains($0) }
    }

    private func scheduleTerminalDisplayTitleUpdate() {
        lock.lock()
        guard terminalDisplayTitleUpdateScheduled == false else {
            lock.unlock()
            return
        }
        terminalDisplayTitleUpdateScheduled = true
        let now = Date()
        let delay = pendingTerminalDisplayTitlePaneIDs
            .compactMap { paneID -> TimeInterval? in
                guard let lastUpdate = lastTerminalDisplayTitleUpdateByPane[paneID] else {
                    return 0
                }
                return max(0, terminalDisplayTitleUpdateMinimumInterval - now.timeIntervalSince(lastUpdate))
            }
            .min() ?? terminalDisplayTitleUpdateMinimumInterval
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.flushTerminalDisplayTitleUpdates()
        }
    }

    private func flushTerminalDisplayTitleUpdates() {
        var updatedWorkspaceIDs = Set<WorkspaceID>()
        let now = Date()

        lock.lock()
        let paneIDs = pendingTerminalDisplayTitlePaneIDs
        pendingTerminalDisplayTitlePaneIDs.removeAll()
        terminalDisplayTitleUpdateScheduled = false

        for paneID in paneIDs {
            guard let location = paneLocationLocked(for: paneID),
                  let resolved = workspacePaneLocked(at: location),
                  let reportedTitle = resolved.pane.terminalState.reportedTitle,
                  let displayTitle = Self.displayTitle(forReportedTerminalTitle: reportedTitle),
                  deliveredTerminalDisplayTitleByPane[paneID] != displayTitle
            else {
                continue
            }

            guard shouldApplyTerminalDisplayTitleUpdateLocked(for: paneID, at: now) else {
                pendingTerminalDisplayTitlePaneIDs.insert(paneID)
                continue
            }

            lastTerminalDisplayTitleUpdateByPane[paneID] = now
            _ = workspaces[location.workspaceIndex].updatePane(paneID) { pane in
                if pane.userAlias == nil,
                   Self.shouldPromoteTerminalDisplayTitleToPaneTitle(displayTitle),
                   pane.title != displayTitle {
                    pane.title = displayTitle
                    deliveredTerminalDisplayTitleByPane[paneID] = displayTitle
                }
            }
            updatedWorkspaceIDs.insert(workspaces[location.workspaceIndex].id)
        }
        let shouldReschedule = pendingTerminalDisplayTitlePaneIDs.isEmpty == false
        lock.unlock()

        if shouldReschedule {
            scheduleTerminalDisplayTitleUpdate()
        }
        for workspaceID in updatedWorkspaceIDs {
            scheduleTerminalStateChangeUpdate(for: workspaceID)
        }
    }

    private func flushTerminalStateChangeUpdates() {
        let updatedWorkspaces: [Workspace]

        lock.lock()
        let pendingIDs = pendingTerminalStateWorkspaceIDs
        pendingTerminalStateWorkspaceIDs.removeAll()
        terminalStateChangeUpdateScheduled = false
        updatedWorkspaces = workspaces.filter { pendingIDs.contains($0.id) }
        lock.unlock()

        for workspace in updatedWorkspaces {
            onChange?(workspace)
        }
    }

    private func scheduleProgressIdleClear(for paneID: PaneID, token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + progressIdleClearDelay) { [weak self] in
            self?.clearProgressIdleState(for: paneID, token: token)
        }
    }

    private func handleIdleProgressSetLocked(for paneID: PaneID, workspaceIndex: Int) {
        switch paneConfiguration.idleStatusClear {
        case .onFocus:
            progressIdleClearTokens.removeValue(forKey: paneID)
            if isFocusedInActiveWorkspaceLocked(paneID: paneID, workspaceIndex: workspaceIndex) {
                _ = clearIdleProgressLocked(for: paneID, workspaceIndex: workspaceIndex)
            }
        case .afterDelay:
            let token = UUID()
            progressIdleClearTokens[paneID] = token
            scheduleProgressIdleClear(for: paneID, token: token)
        case .never:
            progressIdleClearTokens.removeValue(forKey: paneID)
        }
    }

    private func clearIdleProgressOnFocusLocked(for paneID: PaneID, workspaceIndex: Int) -> Bool {
        guard paneConfiguration.idleStatusClear == .onFocus else {
            return false
        }
        progressIdleClearTokens.removeValue(forKey: paneID)
        return clearIdleProgressLocked(for: paneID, workspaceIndex: workspaceIndex)
    }

    private func clearIdleProgressLocked(for paneID: PaneID, workspaceIndex: Int) -> Bool {
        workspaces[workspaceIndex].updatePane(paneID) { pane in
            guard pane.terminalState.progress?.state == .paused else {
                return
            }
            pane.terminalState.progress = nil
            aiStatusManagedAdapterByPaneID.removeValue(forKey: paneID)
        }
    }

    private func isFocusedInActiveWorkspaceLocked(paneID: PaneID, workspaceIndex: Int) -> Bool {
        activeWorkspaceID == workspaces[workspaceIndex].id && workspaces[workspaceIndex].focusedPane?.id == paneID
    }

    private func clearProgressIdleState(for paneID: PaneID, token: UUID) {
        var updatedWorkspaceID: WorkspaceID?

        lock.lock()
        guard progressIdleClearTokens[paneID] == token else {
            lock.unlock()
            return
        }
        guard paneConfiguration.idleStatusClear == .afterDelay else {
            progressIdleClearTokens.removeValue(forKey: paneID)
            lock.unlock()
            return
        }

        for workspaceIndex in workspaces.indices {
            guard workspaces[workspaceIndex].panes.contains(where: { $0.id == paneID }) else {
                continue
            }

            _ = workspaces[workspaceIndex].updatePane(paneID) { pane in
                guard pane.terminalState.progress?.state == .paused else {
                    return
                }
                pane.terminalState.progress = nil
                aiStatusManagedAdapterByPaneID.removeValue(forKey: paneID)
            }
            progressIdleClearTokens.removeValue(forKey: paneID)
            updatedWorkspaceID = workspaces[workspaceIndex].id
            break
        }
        lock.unlock()

        if let updatedWorkspaceID {
            scheduleTerminalStateChangeUpdate(for: updatedWorkspaceID)
        }
    }

    private func paneStatusPayload(
        state: ControlPlanePaneStatusState,
        value: Int?,
        label: String?,
        message: String?,
        source: String
    ) -> OmuxValue {
        .object([
            "state": .string(state.rawValue),
            "value": value.map(OmuxValue.integer) ?? .null,
            "label": label.map(OmuxValue.string) ?? .null,
            "message": message.map(OmuxValue.string) ?? .null,
            "source": .string(source),
        ])
    }

    private func applyAIStatusTitleObservationLocked(
        title: String,
        paneID: PaneID,
        workspaceIndex: Int,
        pane: inout Pane,
        shouldHandleIdle: inout Bool
    ) -> Bool {
        _ = workspaceIndex
        guard aiStatusConfiguration.enabled else {
            return false
        }

        if let observation = OmuxAIStatusTitleObserver.observe(
            title: title,
            previousAdapterID: aiStatusManagedAdapterByPaneID[paneID]
        ) {
            let progress = paneProgress(forAIStatusState: observation.state)
            guard pane.terminalState.progress != progress || pane.terminalState.agentStatusAdapterID != observation.adapterID else {
                aiStatusManagedAdapterByPaneID[paneID] = observation.adapterID
                return false
            }
            pane.terminalState.progress = progress
            pane.terminalState.agentStatusAdapterID = observation.adapterID
            aiStatusManagedAdapterByPaneID[paneID] = observation.adapterID
            if observation.state == .idle {
                shouldHandleIdle = true
            } else {
                progressIdleClearTokens.removeValue(forKey: paneID)
            }
            return true
        }

        guard aiStatusManagedAdapterByPaneID[paneID] != nil,
              pane.terminalState.progress != nil
        else {
            return false
        }
        let idleProgress = PaneProgress(state: .paused)
        if pane.terminalState.progress == idleProgress,
           pane.terminalState.agentStatusAdapterID == nil {
            return false
        }
        pane.terminalState.progress = idleProgress
        pane.terminalState.agentStatusAdapterID = nil
        shouldHandleIdle = true
        return true
    }

    private func paneProgress(forAIStatusState state: ControlPlanePaneStatusState) -> PaneProgress? {
        switch state {
        case .working:
            return PaneProgress(state: .active)
        case .indeterminate:
            return PaneProgress(state: .indeterminate)
        case .error:
            return PaneProgress(state: .error)
        case .needsInput:
            return PaneProgress(state: .needsInput)
        case .idle:
            return PaneProgress(state: .paused)
        case .clear:
            return nil
        }
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

    private func makePane(
        title: String,
        workingDirectory: String,
        workspaceID: WorkspaceID,
        workspaceRootPath: String,
        shellEnvironment: WorkspaceShellEnvironment
    ) throws -> Pane {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let baseSession = SessionDescriptor(shell: shell, workingDirectory: workingDirectory)
        try shellEnvironment.prepareHistoryStorage(for: workspaceID)
        let session = shellEnvironment.applyingWorkspaceContext(
            to: baseSession,
            workspaceID: workspaceID,
            workspaceRootPath: workspaceRootPath
        )
        return Pane(title: title, session: session)
    }

    private func sanitizedWorkspaceForPersistence(
        _ workspace: Workspace,
        mode: WorkspacePersistenceSnapshotMode,
        historyClearSuppression: [PaneID: String]
    ) -> Workspace {
        Workspace(
            id: workspace.id,
            generatedName: workspace.generatedName,
            customName: workspace.customName,
            rootPath: workspace.rootPath,
            tabs: workspace.tabs.map {
                sanitizedTabForPersistence($0, mode: mode, historyClearSuppression: historyClearSuppression)
            },
            focusedTabID: workspace.focusedTabID,
            floatingPaneModals: workspace.floatingPaneModals.map {
                FloatingPaneModal(
                    id: $0.id,
                    paneStack: PaneStack(
                        id: $0.paneStack.id,
                        panes: $0.paneStack.panes.map {
                            sanitizedPaneForPersistence($0, mode: mode, historyClearSuppression: historyClearSuppression)
                        },
                        focusedPaneID: $0.paneStack.focusedPaneID
                    ),
                    frame: $0.frame
                )
            },
            focusedFloatingPaneModalID: workspace.focusedFloatingPaneModalID
        )
    }

    private func sanitizedTabForPersistence(
        _ tab: Tab,
        mode: WorkspacePersistenceSnapshotMode,
        historyClearSuppression: [PaneID: String]
    ) -> Tab {
        Tab(
            id: tab.id,
            title: tab.title,
            rootLayout: sanitizedLayoutNodeForPersistence(
                tab.rootLayout,
                mode: mode,
                historyClearSuppression: historyClearSuppression
            ),
            focusedPaneID: tab.focusedPaneID
        )
    }

    private func sanitizedLayoutNodeForPersistence(
        _ node: TabLayoutNode,
        mode: WorkspacePersistenceSnapshotMode,
        historyClearSuppression: [PaneID: String]
    ) -> TabLayoutNode {
        switch node {
        case .paneStack(let paneStack):
            let panes = paneStack.panes.map {
                sanitizedPaneForPersistence($0, mode: mode, historyClearSuppression: historyClearSuppression)
            }
            return .paneStack(
                PaneStack(
                    id: paneStack.id,
                    panes: panes,
                    focusedPaneID: paneStack.focusedPaneID
                )
            )
        case .split(let axis, let proportions, let children):
            return .split(
                axis: axis,
                proportions: proportions,
                children: children.map {
                    sanitizedLayoutNodeForPersistence(
                        $0,
                        mode: mode,
                        historyClearSuppression: historyClearSuppression
                    )
                }
            )
        }
    }

    private func sanitizedPaneForPersistence(
        _ pane: Pane,
        mode: WorkspacePersistenceSnapshotMode,
        historyClearSuppression: [PaneID: String]
    ) -> Pane {
        guard var session = pane.terminalSession else {
            return pane
        }

        let liveSnapshot = bridge.snapshot(for: pane.id)
        if let workingDirectory = pane.terminalState.reportedWorkingDirectory, workingDirectory.isEmpty == false {
            session.workingDirectory = workingDirectory
        } else if let workingDirectory = liveSnapshot?.workingDirectory, workingDirectory.isEmpty == false {
            session.workingDirectory = workingDirectory
        }
        let restoredScrollback: PaneScrollbackSnapshot?
        switch mode {
        case .layoutOnly:
            restoredScrollback = pane.terminalState.restoredScrollback
        case .includeScrollback(let maxBytes, let maxLines):
            let liveSnapshot = bridge.scrollbackSnapshot(
                for: pane.id,
                maxBytes: maxBytes,
                maxLines: maxLines
            )
            if let liveSnapshot {
                if liveSnapshot.text == historyClearSuppression[pane.id] {
                    restoredScrollback = nil
                } else {
                    restoredScrollback = sanitizedRestoredScrollback(
                        liveSnapshot,
                        maxBytes: maxBytes,
                        maxLines: maxLines
                    )
                }
            } else {
                let plainSnapshot = bridge.terminalTextSnapshot(
                    for: pane.id,
                    maxBytes: maxBytes,
                    maxLines: maxLines
                )
                if plainSnapshot.isAvailable {
                    if plainSnapshot.scrollbackSnapshot?.text == historyClearSuppression[pane.id] {
                        restoredScrollback = nil
                    } else {
                        restoredScrollback = plainSnapshot.scrollbackSnapshot.flatMap {
                            sanitizedRestoredScrollback($0, maxBytes: maxBytes, maxLines: maxLines)
                        }
                    }
                } else {
                    restoredScrollback = historyClearSuppression[pane.id] == nil ? pane.terminalState.restoredScrollback : nil
                }
            }
        }
        var updatedPane = pane
        updatedPane.session = session
        updatedPane.terminalState = PaneTerminalState(restoredScrollback: restoredScrollback)
        return updatedPane
    }

    private func sanitizedRestoredScrollback(
        _ snapshot: PaneScrollbackSnapshot,
        maxBytes: Int,
        maxLines: Int
    ) -> PaneScrollbackSnapshot? {
        PaneScrollbackSnapshot.bounded(
            text: TerminalScrollbackTextSanitizer.sanitizedForReplayOrPersistence(snapshot.text),
            maxBytes: maxBytes,
            maxLines: maxLines
        ).map { sanitized in
            PaneScrollbackSnapshot(
                text: sanitized.text,
                truncated: sanitized.truncated || snapshot.truncated,
                storageIdentifier: snapshot.storageIdentifier
            )
        }
    }

    private static func sanitizedPaneForRestore(_ pane: Pane) -> Pane {
        var restoredPane = pane
        restoredPane.terminalState = PaneTerminalState(restoredScrollback: pane.terminalState.restoredScrollback)
        return restoredPane
    }

    private static func normalizedRestoredWorkspace(_ workspace: Workspace) -> Workspace? {
        let normalizedTabs = workspace.tabs.compactMap(normalizedRestoredTab)
        let normalizedFloatingPaneModals = workspace.floatingPaneModals.compactMap { modal -> FloatingPaneModal? in
            let restoredPanes = modal.paneStack.panes.map(sanitizedPaneForRestore)
            guard restoredPanes.isEmpty == false else {
                return nil
            }
            let focusedPaneID = restoredPanes.contains(where: { $0.id == modal.paneStack.focusedPaneID })
                ? modal.paneStack.focusedPaneID
                : restoredPanes[0].id
            return FloatingPaneModal(
                id: modal.id,
                paneStack: PaneStack(id: modal.paneStack.id, panes: restoredPanes, focusedPaneID: focusedPaneID),
                frame: modal.frame
            )
        }
        guard normalizedTabs.isEmpty == false || normalizedFloatingPaneModals.isEmpty == false else {
            return nil
        }

        let focusedTabID = normalizedTabs.contains(where: { $0.id == workspace.focusedTabID })
            ? workspace.focusedTabID
            : normalizedTabs.first?.id ?? TabID()
        let focusedFloatingPaneModalID = normalizedFloatingPaneModals.contains(where: { $0.id == workspace.focusedFloatingPaneModalID })
            ? workspace.focusedFloatingPaneModalID
            : nil

        return Workspace(
            id: workspace.id,
            generatedName: workspace.generatedName,
            customName: workspace.customName,
            rootPath: workspace.rootPath,
            tabs: normalizedTabs,
            focusedTabID: focusedTabID,
            floatingPaneModals: normalizedFloatingPaneModals,
            focusedFloatingPaneModalID: focusedFloatingPaneModalID
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
            let panes = paneStack.panes.map(sanitizedPaneForRestore)
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
        case .split(let axis, let proportions, let children):
            let normalizedChildren = children.map(normalizedRestoredLayoutNode)
            return .split(axis: axis, proportions: proportions, children: normalizedChildren)
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
                if pane.isTerminal {
                    try bridge.teardown(paneID: pane.id)
                }
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
            if removedPane.isTerminal {
                try bridge.teardown(paneID: removedPane.id)
            }
            try hookRunner.emit(
                HookInvocation(
                    category: .session,
                    name: "pane-tab-closed",
                    workspaceID: updatedWorkspaceID,
                    tabID: updatedTabID,
                    paneID: removedPane.id,
                    sessionID: removedPane.terminalSession?.id,
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

private extension PaneHistoryTarget {
    func historyItem(
        text: String,
        truncated: Bool,
        unavailable: String? = nil
    ) -> ControlPlanePaneHistoryItem {
        ControlPlanePaneHistoryItem(
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            tabID: tabID,
            tabTitle: tabTitle,
            paneStackID: paneStackID,
            paneID: paneID,
            paneTitle: paneTitle,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            text: text,
            truncated: truncated,
            unavailable: unavailable
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func isContained(in directory: String) -> Bool {
        self == directory || hasPrefix(directory + "/")
    }
}

private extension Character {
    var isTerminalTitleSpinnerGlyph: Bool {
        guard unicodeScalars.count == 1,
              let scalar = unicodeScalars.first
        else {
            return false
        }

        if (0x2800...0x28FF).contains(Int(scalar.value)) {
            return true
        }

        switch scalar {
        case "•", "●", "◦", "○",
             "◐", "◓", "◑", "◒",
             "◜", "◠", "◝", "◞", "◡", "◟",
             "⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈":
            return true
        default:
            return false
        }
    }
}
