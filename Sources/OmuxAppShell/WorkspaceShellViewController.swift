import AppKit
import OmuxAIStatusPlugin
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxTerminalBridge
import OmuxVault
import QuartzCore
import WebKit

@MainActor
final class WorkspaceShellViewController: NSViewController {
    enum VaultWorkspaceFilter: Equatable {
        case current
        case all
        case workspace(WorkspaceID)
    }

    private enum CachedTerminalText {
        case loaded(String?)
    }

    private struct SidebarRowValues {
        let row1: String?
        let row2: String?
        let row3: String?
    }

    private struct PaneMetadataRowsOverride {
        var row1: String?
        var row2: String?
        var row3: String?

        var isEmpty: Bool {
            row1 == nil && row2 == nil && row3 == nil
        }
    }

    private final class TerminalTextRenderCache {
        private var cachedTextByPaneID: [PaneID: CachedTerminalText] = [:]

        func text(for pane: Pane, load: () -> String?) -> String? {
            if case .loaded(let text)? = cachedTextByPaneID[pane.id] {
                return text
            }

            let text = load()
            cachedTextByPaneID[pane.id] = .loaded(text)
            return text
        }
    }

    private let controller: WorkspaceController
    private let metadataResolver = TerminalSidebarMetadataResolver()
    private let iconResolver = WorkspaceIconResolver()
    private let sidebarView = WorkspaceSidebarView()
    private let vaultSidebarView = WorkspaceVaultSidebarView()
    private let topBarBackgroundView = NSView()
    private let topBarBorderView = NSView()
    private let sidebarToggleButton = TitleBarButton()
    private let vaultToggleButton = TitleBarButton()
    private let canvasView = WorkspaceCanvasView()
    private let shellOverlayHostView = ShellOverlayHostView()
    private let sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var vaultSidebarWidthConstraint: NSLayoutConstraint?
    private var mainColumnLeadingConstraint: NSLayoutConstraint?
    private var mainColumnTrailingConstraint: NSLayoutConstraint?
    private var currentWorkspace: Workspace?
    private var currentTheme: WorkspaceShellTheme
    private var currentPanes: OmuxConfigUI.Panes
    private var currentIcons: OmuxConfigUI.Icons
    private var currentSidebar: OmuxConfigUI.Sidebar
    private var isSidebarVisible: Bool
    private var applicationIsActive: Bool = NSApplication.shared.isActive
    private var windowIsKey: Bool = false
    private var focusRestoreGeneration: UInt = 0
    private var terminalIconRefreshTimer: Timer?
    private var renderedIconKindByPaneID: [PaneID: OmuxSemanticIcon.Kind] = [:]
    private var commandPaletteView: CommandPaletteView?
    private var paneFindBarView: PaneFindBarView?
    private let vaultStore: VaultStore?
    private let vaultConfiguration: VaultConfiguration
    private var vaultSessions: [VaultSessionSummary] = []
    private var vaultLoadGeneration = UUID()
    private var vaultAgentLoadGeneration = UUID()
    private var vaultSearchQuery = ""
    private var vaultAgentFilter: VaultAgentKind?
    private var availableVaultAgents = Set<VaultAgentKind>()
    private var vaultResultOffset = 0
    private var vaultHasMore = true
    private var vaultIsLoading = false
    private var isVaultSidebarVisible = false
    private var vaultWorkspaceFilter: VaultWorkspaceFilter = .current
    private var activeVaultSessionByPaneID: [PaneID: String] = [:]
    private var vaultPaletteSessions: [VaultSessionSummary] = []
    private var vaultPaletteEntries: [VaultPaletteEntry] = []
    private var vaultPaletteLoadGeneration = UUID()
    private var vaultPaletteSessionsLoaded = false
    private var vaultIndexRefreshCoordinator: VaultIndexRefreshCoordinator?
    private var vaultSourceEventWatcher: VaultSourceEventWatcher?
    private var findSearchObserverToken: UUID?
    private var collapsedWorkspaceIDs = Set<WorkspaceID>()
    private var worktrees: [GitWorktree] = []
    private var worktreeBranches: [String] = []
    private var isWorktreesSectionCollapsed: Bool = UserDefaults.standard.bool(forKey: "omux.rightSidebar.worktreesCollapsed")
    private var isAgentSessionsSectionCollapsed: Bool = UserDefaults.standard.bool(forKey: "omux.rightSidebar.agentSessionsCollapsed")
    private var isWorkspacesSectionCollapsed: Bool = UserDefaults.standard.bool(forKey: "omux.leftSidebar.workspacesCollapsed")
    private var paneMetadataRowsOverridesByPaneID: [PaneID: PaneMetadataRowsOverride] = [:]
    private let onClosePaneTab: @MainActor (PaneID) -> Void
    private let onExtensionPaneAction: @MainActor (ExtensionPaneActionRequest) -> Void
    private var sidebarDragCoordinator: SidebarDragCoordinator?

    private var floatingModalOverlayView: FloatingModalOverlayView {
        shellOverlayHostView.floatingModalOverlayView
    }

    var themeCommitHandler: ((String) -> Void)?

    init(
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme,
        initialPanes: OmuxConfigUI.Panes,
        initialIcons: OmuxConfigUI.Icons,
        initialSidebar: OmuxConfigUI.Sidebar,
        vaultStore: VaultStore?,
        vaultConfiguration: VaultConfiguration,
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring,
        onClosePaneTab: @escaping @MainActor (PaneID) -> Void,
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void
    ) {
        self.controller = controller
        self.currentTheme = initialTheme
        self.currentPanes = initialPanes
        self.currentIcons = initialIcons
        self.currentSidebar = initialSidebar
        self.vaultStore = vaultStore
        self.vaultConfiguration = vaultConfiguration
        self.sidebarVisibilityStore = sidebarVisibilityStore
        self.isSidebarVisible = sidebarVisibilityStore.isSidebarVisible
        self.onClosePaneTab = onClosePaneTab
        self.onExtensionPaneAction = onExtensionPaneAction
        super.init(nibName: nil, bundle: nil)
        configureVaultSourceIndexing()
        subscribeToCommandFinished()
    }

    deinit {
        MainActor.assumeIsolated {
            stopFindSearch()
            terminalIconRefreshTimer?.invalidate()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = WorkspaceRootView()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.wantsLayer = true

        let mainColumn = NSStackView()
        mainColumn.orientation = .vertical
        mainColumn.alignment = .width
        mainColumn.distribution = .fill
        mainColumn.spacing = 0
        mainColumn.translatesAutoresizingMaskIntoConstraints = false

        mainColumn.addArrangedSubview(canvasView)

        sidebarToggleButton.isBordered = false
        sidebarToggleButton.image = NSImage(systemSymbolName: "sidebar.squares.left", accessibilityDescription: "Toggle Workspace Sidebar")
        sidebarToggleButton.toolTip = "Toggle Workspace Sidebar (⌘B)"
        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(toggleSidebarPressed)
        sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false

        vaultToggleButton.isBordered = false
        vaultToggleButton.image = NSImage(systemSymbolName: "sidebar.squares.right", accessibilityDescription: "Toggle Right Sidebar")
        vaultToggleButton.identifier = NSUserInterfaceItemIdentifier(A11yID.vaultSidebarToggle.rawValue)
        vaultToggleButton.setAccessibilityIdentifier(A11yID.vaultSidebarToggle)
        vaultToggleButton.toolTip = "Toggle Right Sidebar (⇧⌘B)"
        vaultToggleButton.target = self
        vaultToggleButton.action = #selector(toggleVaultSidebarPressed)
        vaultToggleButton.translatesAutoresizingMaskIntoConstraints = false

        topBarBackgroundView.wantsLayer = true
        topBarBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        topBarBorderView.wantsLayer = true
        topBarBorderView.translatesAutoresizingMaskIntoConstraints = false

        sidebarView.setAccessibilityIdentifier(A11yID.workspaceList)
        canvasView.setAccessibilityIdentifier(A11yID.paneContainer)
        vaultSidebarView.setAccessibilityIdentifier(A11yID.vaultSidebar)
        view.addSubview(topBarBackgroundView)
        view.addSubview(topBarBorderView)
        view.addSubview(sidebarView)
        view.addSubview(mainColumn)
        view.addSubview(sidebarToggleButton)
        view.addSubview(vaultSidebarView)
        if vaultConfiguration.collapsedToggleVisible {
            view.addSubview(vaultToggleButton)
        }
        view.addSubview(shellOverlayHostView)

        let sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.sidebarWidth)
        let vaultSidebarWidthConstraint = vaultSidebarView.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultSidebarWidth)
        let mainColumnLeadingConstraint = mainColumn.leadingAnchor.constraint(
            equalTo: sidebarView.trailingAnchor,
            constant: ShellLayoutMetrics.interRegionSpacing
        )
        let mainColumnTrailingConstraint = mainColumn.trailingAnchor.constraint(
            equalTo: vaultSidebarView.leadingAnchor,
            constant: -ShellLayoutMetrics.interRegionSpacing
        )
        self.sidebarWidthConstraint = sidebarWidthConstraint
        self.vaultSidebarWidthConstraint = vaultSidebarWidthConstraint
        self.mainColumnLeadingConstraint = mainColumnLeadingConstraint
        self.mainColumnTrailingConstraint = mainColumnTrailingConstraint

        var constraints = [
            sidebarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidthConstraint,

            mainColumn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ShellLayoutMetrics.outerPadding),
            mainColumnLeadingConstraint,
            mainColumnTrailingConstraint,
            mainColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -ShellLayoutMetrics.outerPadding),
            canvasView.widthAnchor.constraint(equalTo: mainColumn.widthAnchor),
        ]

        // A layout guide spanning the native title bar area, used to vertically
        // center all top bar buttons regardless of the actual title bar height.
        let titleBarGuide = NSLayoutGuide()
        view.addLayoutGuide(titleBarGuide)
        constraints += [
            titleBarGuide.topAnchor.constraint(equalTo: view.topAnchor),
            titleBarGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            titleBarGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBarGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            topBarBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            topBarBackgroundView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBarBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            topBarBorderView.heightAnchor.constraint(equalToConstant: 1),
            topBarBorderView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBarBorderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarBorderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]

        if vaultConfiguration.collapsedToggleVisible {
            constraints += [
                vaultToggleButton.centerYAnchor.constraint(equalTo: titleBarGuide.centerYAnchor),
                vaultToggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                vaultToggleButton.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultToggleSize),
                vaultToggleButton.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultToggleSize),
            ]
        }

        constraints += [
            vaultSidebarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            vaultSidebarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vaultSidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            vaultSidebarWidthConstraint,
        ]

        // Sidebar toggle button: always present, positioned to the left of the
        // vault toggle (or at the trailing edge when vault toggle is hidden).
        let sidebarButtonTrailing = vaultConfiguration.collapsedToggleVisible
            ? vaultToggleButton.leadingAnchor
            : view.trailingAnchor
        constraints += [
            sidebarToggleButton.centerYAnchor.constraint(equalTo: titleBarGuide.centerYAnchor),
            sidebarToggleButton.trailingAnchor.constraint(equalTo: sidebarButtonTrailing),
            sidebarToggleButton.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultToggleSize),
            sidebarToggleButton.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultToggleSize),
        ]

        constraints += [
            shellOverlayHostView.topAnchor.constraint(equalTo: mainColumn.topAnchor),
            shellOverlayHostView.leadingAnchor.constraint(equalTo: mainColumn.leadingAnchor),
            shellOverlayHostView.trailingAnchor.constraint(equalTo: mainColumn.trailingAnchor),
            shellOverlayHostView.bottomAnchor.constraint(equalTo: mainColumn.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

        configureSidebarPanelsFromDefaults()

        // Wire cross-sidebar drag coordinator.
        sidebarDragCoordinator = SidebarDragCoordinator(
            leftSplit: sidebarView.splitView,
            rightSplit: vaultSidebarView.splitView,
            leftSidebarView: sidebarView,
            rightSidebarView: vaultSidebarView
        )
        sidebarView.splitView.onPanelOrderChanged = { [weak self] in
            self?.persistSidebarPanelOrder()
        }
        vaultSidebarView.splitView.onPanelOrderChanged = { [weak self] in
            self?.persistSidebarPanelOrder()
        }
        sidebarDragCoordinator?.onPanelOrderChanged = { [weak self] in
            self?.persistSidebarPanelOrder()
        }

        applySidebarVisibility()
        applyVaultSidebarVisibility()
        startTerminalIconRefreshTimer()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: view.window
        )
        nc.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: view.window
        )
        nc.addObserver(
            self,
            selector: #selector(windowPresentationStateDidChange(_:)),
            name: NSWindow.didMiniaturizeNotification,
            object: view.window
        )
        nc.addObserver(
            self,
            selector: #selector(windowPresentationStateDidChange(_:)),
            name: NSWindow.didDeminiaturizeNotification,
            object: view.window
        )
        nc.addObserver(
            self,
            selector: #selector(windowPresentationStateDidChange(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: view.window
        )
        nc.addObserver(
            self,
            selector: #selector(applicationPresentationStateDidChange(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: NSApplication.shared
        )
        nc.addObserver(
            self,
            selector: #selector(applicationPresentationStateDidChange(_:)),
            name: NSApplication.didResignActiveNotification,
            object: NSApplication.shared
        )
        nc.addObserver(
            self,
            selector: #selector(applicationPresentationStateDidChange(_:)),
            name: NSApplication.didHideNotification,
            object: NSApplication.shared
        )
        nc.addObserver(
            self,
            selector: #selector(applicationPresentationStateDidChange(_:)),
            name: NSApplication.didUnhideNotification,
            object: NSApplication.shared
        )
        applicationIsActive = NSApplication.shared.isActive
        windowIsKey = view.window?.isKeyWindow ?? false
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: view.window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: view.window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMiniaturizeNotification, object: view.window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didDeminiaturizeNotification, object: view.window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: view.window)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didHideNotification, object: NSApplication.shared)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didUnhideNotification, object: NSApplication.shared)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard windowIsKey == false else {
            return
        }
        windowIsKey = true
        if let workspace = controller.activeWorkspace() ?? currentWorkspace {
            refreshTerminalPresentation(for: workspace, restoreFocusIfPossible: true)
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard windowIsKey else {
            return
        }
        windowIsKey = false
        if let workspace = controller.activeWorkspace() ?? currentWorkspace {
            refreshTerminalPresentation(for: workspace)
        }
    }

    @objc private func windowPresentationStateDidChange(_ notification: Notification) {
        _ = notification
        if let workspace = controller.activeWorkspace() ?? currentWorkspace {
            refreshTerminalPresentation(for: workspace)
        }
    }

    @objc private func applicationPresentationStateDidChange(_ notification: Notification) {
        switch notification.name {
        case NSApplication.didBecomeActiveNotification:
            applicationIsActive = true
        case NSApplication.didResignActiveNotification:
            applicationIsActive = false
        default:
            break
        }
        if let workspace = controller.activeWorkspace() ?? currentWorkspace {
            refreshTerminalPresentation(
                for: workspace,
                restoreFocusIfPossible: notification.name == NSApplication.didBecomeActiveNotification
            )
        }
    }

    private func refreshTerminalPresentation(
        for workspace: Workspace,
        restoreFocusIfPossible: Bool = false
    ) {
        do {
            _ = try controller.ensureVisibleTerminalSurfaces(
                for: workspace.id,
                presentationState: currentTerminalSurfacePresentationState()
            )
        } catch {
            fputs("warning: failed to refresh terminal presentation state: \(error)\n", stderr)
        }
        update(workspace: workspace)

        guard restoreFocusIfPossible,
              currentTerminalSurfacePresentationState().runtimeIsFocused,
              let focusedPaneID = workspace.focusedPane?.id,
              let focusedPaneView = findHostedPaneView(in: canvasView, paneID: focusedPaneID)
                ?? findHostedPaneView(in: floatingModalOverlayView, paneID: focusedPaneID)
        else {
            return
        }
        view.window?.makeFirstResponder(focusTarget(for: focusedPaneView))
    }

    func currentTerminalSurfacePresentationState() -> TerminalSurfacePresentationState {
        guard let window = view.window else {
            return TerminalSurfacePresentationState(
                appIsActive: applicationIsActive,
                windowIsKey: windowIsKey,
                windowIsVisible: false
            )
        }

        let windowIsVisible = window.isMiniaturized == false
            && window.isVisible
            && NSApplication.shared.isHidden == false
            && window.occlusionState.contains(.visible)

        return TerminalSurfacePresentationState(
            appIsActive: applicationIsActive,
            windowIsKey: windowIsKey,
            windowIsVisible: windowIsVisible
        )
    }

    func update(workspace: Workspace) {
        if paneTabDragState != nil {
            deferredWorkspaceUpdateDuringPaneTabDrag = workspace
            return
        }

        let previousWorkspace = currentWorkspace
        let previousWorkspaceID = currentWorkspace?.id
        let previousFocusedPaneID = currentWorkspace?.focusedPane?.id
        let previousFocusedPaneWorkingDirectory = currentWorkspace?.focusedPane?.terminalSession?.workingDirectory
        let shouldRestoreFocus = shouldRestoreFocus(
            previousWorkspaceID: previousWorkspaceID,
            previousFocusedPaneID: previousFocusedPaneID,
            workspace: workspace
        )
        invalidateIconCacheForChangedPaths(from: currentWorkspace, to: workspace)
        let allWorkspaces = controller.allWorkspaces()
        let workspaceIDs = Set(allWorkspaces.map(\.id))
        collapsedWorkspaceIDs = collapsedWorkspaceIDs.intersection(workspaceIDs)
        if previousWorkspaceID != nil, previousWorkspaceID != workspace.id {
            collapsedWorkspaceIDs.remove(workspace.id)
        }
        let allPaneIDs = Set(allWorkspaces.flatMap { workspace in
            workspace.tabs.flatMap(\.panes) + workspace.floatingPaneModals.flatMap(\.panes)
        }.map(\.id))
        paneMetadataRowsOverridesByPaneID = paneMetadataRowsOverridesByPaneID.filter { allPaneIDs.contains($0.key) }
        currentWorkspace = workspace
        dismissIrrelevantRestoreBanners(for: workspace)
        let focusedPaneID = workspace.focusedPane?.id
        let focusedPaneWorkingDirectory = workspace.focusedPane?.terminalSession?.workingDirectory
        // Reload worktrees when focused pane or its working directory changes.
        if previousFocusedPaneID != focusedPaneID
            || previousWorkspaceID != workspace.id
            || previousFocusedPaneWorkingDirectory != focusedPaneWorkingDirectory {
            reloadWorktrees()
        }
        apply(theme: currentTheme)
        let terminalTextCache = TerminalTextRenderCache()
        let terminalTextProvider: @MainActor (Pane) -> String? = { [weak self] pane in
            guard let self else {
                return nil
            }
            return terminalTextCache.text(for: pane) {
                self.terminalScreenText(for: pane)
            }
        }

        let workspaceItems = makeWorkspaceSidebarItems(
            workspaces: allWorkspaces,
            activeWorkspace: workspace,
            terminalTextProvider: terminalTextProvider
        )
        let normalizedWorkspaceFilter = normalizedVaultWorkspaceFilter(for: allWorkspaces)
        if vaultWorkspaceFilter != normalizedWorkspaceFilter {
            vaultWorkspaceFilter = normalizedWorkspaceFilter
        }
        sidebarView.render(
            workspaceItems: workspaceItems,
            isWorkspacesCollapsed: isWorkspacesSectionCollapsed,
            theme: currentTheme,
            onSelectWorkspace: { [weak self] workspaceID in
                _ = self?.controller.restore(workspaceID: workspaceID)
            },
            onCreateWorkspace: { [weak self] in
                _ = try? self?.controller.createWorkspace()
            },
            onDeleteWorkspace: { [weak self] in
                _ = try? self?.controller.deleteActiveWorkspace()
            },
            canDeleteWorkspace: controller.canDeleteActiveWorkspace(),
            updateAvailability: controller.currentUpdateAvailability(),
            onMoveWorkspace: { [weak self] workspaceID, targetIndex in
                _ = self?.controller.moveWorkspace(workspaceID, toDisplayIndex: targetIndex)
            },
            onToggleWorkspaceExpansion: { [weak self] workspaceID in
                self?.toggleWorkspaceExpansion(workspaceID)
            },
            onRenameWorkspace: { [weak self] workspaceID, newName in
                _ = try? self?.controller.renameWorkspace(workspaceID, to: newName)
            },
            onSelectPane: { [weak self] paneID in
                _ = self?.controller.focus(paneID: paneID)
            },
            onToggleWorkspacesCollapse: { [weak self] in
                self?.toggleWorkspacesCollapsed()
            }
        )
        renderVaultSidebar(activeWorkspace: workspace, allWorkspaces: allWorkspaces)
        let plan = WorkspaceRenderReconciliationPlanner.classify(
            previousWorkspaceID: previousWorkspace?.id,
            previousFocusedTabID: previousWorkspace?.focusedTabID,
            previousLayout: previousWorkspace?.focusedTab?.rootLayout,
            nextWorkspaceID: workspace.id,
            nextFocusedTabID: workspace.focusedTabID,
            nextLayout: workspace.focusedTab?.rootLayout
        )

        let layout: (view: NSView, focusedPaneView: NSView?, representativePaneID: PaneID?)?
        var reconciledFocusedPaneView: NSView?
        var reconciliationMetrics = WorkspaceReconciliationMetrics()

        if plan == .nonStructural,
           let focusedTab = workspace.focusedTab,
           let existingLayoutView = canvasView.currentLayoutView,
           let reconciliation = reconcileLayoutView(
               existingView: existingLayoutView,
               node: focusedTab.rootLayout,
               focusedPaneID: focusedTab.focusedPaneID,
               windowIsKey: windowIsKey,
               inactiveOpacity: currentPanes.inactiveOpacity,
               canCloseSinglePaneStack: focusedTab.panes.count > 1 || workspace.tabs.count > 1,
               terminalTextProvider: terminalTextProvider
           ),
           reconciliation.success {
            layout = nil
            reconciledFocusedPaneView = reconciliation.focusedPaneView
            reconciliationMetrics.reusedHostViews = reconciliation.reusedPaneStackViews
            canvasView.apply(theme: currentTheme)
        } else {
            layout = workspace.focusedTab.map {
                makeLayoutView(
                    for: $0.rootLayout,
                    focusedPaneID: $0.focusedPaneID,
                    windowIsKey: windowIsKey,
                    inactiveOpacity: currentPanes.inactiveOpacity,
                    canCloseSinglePaneStack: $0.panes.count > 1 || workspace.tabs.count > 1,
                    terminalTextProvider: terminalTextProvider
                )
            }
            canvasView.render(layoutView: layout?.view, theme: currentTheme)
            reconciliationMetrics.rebuiltHostViews = workspace.focusedTab?.paneStacks.count ?? 0
        }

        logReconciliationMetricsIfNeeded(reconciliationMetrics)
        renderedIconKindByPaneID = iconKindSignature(
            for: workspace,
            terminalTextProvider: terminalTextProvider
        )

        let floatingFocusedPaneView = renderFloatingPaneModals(
            workspace: workspace,
            terminalTextProvider: terminalTextProvider
        )
        let focusedPaneView = floatingFocusedPaneView ?? reconciledFocusedPaneView ?? layout?.focusedPaneView
        if shouldRestoreFocus, let focusedPaneView {
            focusRestoreGeneration &+= 1
            let generation = focusRestoreGeneration
            if let window = view.window {
                window.makeFirstResponder(focusTarget(for: focusedPaneView))
            } else {
                DispatchQueue.main.async { [weak self, weak focusedPaneView] in
                    guard let self,
                          let focusedPaneView,
                          self.focusRestoreGeneration == generation
                    else {
                        return
                    }

                    self.view.window?.makeFirstResponder(self.focusTarget(for: focusedPaneView))
                }
            }
        }

        if previousWorkspaceID != workspace.id || previousFocusedPaneID != focusedPaneID {
            reapplyActiveFindSearch(previousPaneID: previousFocusedPaneID)
        }
    }

    func updateTheme(_ theme: WorkspaceShellTheme) {
        currentTheme = theme
        apply(theme: theme)
        if let currentWorkspace {
            update(workspace: currentWorkspace)
        }
    }

    func updateIcons(_ icons: OmuxConfigUI.Icons) {
        currentIcons = icons
        if let currentWorkspace {
            update(workspace: currentWorkspace)
        }
    }

    func updatePanes(_ panes: OmuxConfigUI.Panes) {
        currentPanes = panes
        if let currentWorkspace {
            update(workspace: currentWorkspace)
        }
    }

    func updateSidebar(_ sidebar: OmuxConfigUI.Sidebar) {
        currentSidebar = sidebar
        if let currentWorkspace {
            update(workspace: currentWorkspace)
        }
    }

    @discardableResult
    func setPaneMetadataRows(
        paneID: PaneID,
        row1: String?,
        row2: String?,
        row3: String?,
        source: String? = nil
    ) -> Bool {
        guard controller.pane(paneID) != nil else {
            return false
        }
        var override = PaneMetadataRowsOverride()
        override.row1 = Self.normalizedPaneMetadataOverrideValue(row1)
        override.row2 = Self.normalizedPaneMetadataOverrideValue(row2)
        override.row3 = Self.normalizedPaneMetadataOverrideValue(row3)
        if override.isEmpty {
            paneMetadataRowsOverridesByPaneID.removeValue(forKey: paneID)
        } else {
            paneMetadataRowsOverridesByPaneID[paneID] = override
        }
        if let currentWorkspace = controller.activeWorkspace() ?? currentWorkspace {
            update(workspace: currentWorkspace)
        }
        controller.publishPaneMetadataChange(paneID: paneID, source: source)
        return true
    }

    @discardableResult
    func clearPaneMetadataRows(paneID: PaneID, source: String? = nil) -> Bool {
        guard controller.pane(paneID) != nil else {
            return false
        }
        paneMetadataRowsOverridesByPaneID.removeValue(forKey: paneID)
        if let currentWorkspace = controller.activeWorkspace() ?? currentWorkspace {
            update(workspace: currentWorkspace)
        }
        controller.publishPaneMetadataChange(paneID: paneID, source: source)
        return true
    }

    private func invalidateIconCacheForChangedPaths(from previousWorkspace: Workspace?, to workspace: Workspace) {
        guard let previousWorkspace else {
            return
        }

        let previousPaths = Dictionary(
            uniqueKeysWithValues: previousWorkspace.tabs
                .flatMap(\.panes)
                .map {
                    (
                        $0.id,
                        iconResolutionPath(
                            for: $0,
                            workingDirectory: $0.terminalState.reportedWorkingDirectory
                                ?? $0.terminalSession?.workingDirectory
                        )
                    )
                }
        )

        for pane in workspace.tabs.flatMap(\.panes) {
            let path = iconResolutionPath(for: pane)
            if let previousPath = previousPaths[pane.id], previousPath != path {
                iconResolver.invalidate(path: previousPath)
                iconResolver.invalidate(path: path)
            } else if previousPaths[pane.id] == nil {
                iconResolver.invalidate(path: path)
            }
        }
    }

    private func iconResolutionPath(for pane: Pane, workingDirectory: String? = nil) -> String {
        workingDirectory
            ?? controller.workingDirectory(for: pane.id)
            ?? pane.extensionPane?.source
            ?? pane.id.rawValue
    }

    private static func normalizedPaneMetadataOverrideValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func apply(theme: WorkspaceShellTheme) {
        view.layer?.backgroundColor = theme.shell.windowBackground.cgColor
        view.window?.backgroundColor = theme.shell.windowBackground
        topBarBackgroundView.layer?.backgroundColor = theme.shell.topBarBackground.cgColor
        topBarBorderView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        sidebarView.apply(theme: theme)
        vaultSidebarView.apply(theme: theme)
        vaultToggleButton.contentTintColor = theme.shell.textMuted
        sidebarToggleButton.contentTintColor = theme.shell.textMuted
        canvasView.apply(theme: theme)
        commandPaletteView?.apply(theme: theme)
        shellOverlayHostView.apply(theme: theme)
    }

    private func shouldRestoreFocus(
        previousWorkspaceID: WorkspaceID?,
        previousFocusedPaneID: PaneID?,
        workspace: Workspace
    ) -> Bool {
        let focusedPaneID = workspace.focusedPane?.id
        if previousWorkspaceID != workspace.id || previousFocusedPaneID != focusedPaneID {
            return true
        }

        return wasFocusedPaneFirstResponder(paneID: focusedPaneID)
    }

    private func wasFocusedPaneFirstResponder(paneID: PaneID?) -> Bool {
        guard let paneID,
              let firstResponder = view.window?.firstResponder as? NSView,
              let paneView = findHostedPaneView(in: canvasView, paneID: paneID)
                ?? findHostedPaneView(in: floatingModalOverlayView, paneID: paneID)
        else {
            return false
        }

        let focusTarget = focusTarget(for: paneView)
        return firstResponder === focusTarget || firstResponder.isDescendant(of: focusTarget)
    }

    private func findHostedPaneView(in rootView: NSView, paneID: PaneID) -> NSView? {
        if let paneView = rootView as? any WorkspacePaneRendering, paneView.representedPaneID == paneID {
            return paneView.rootPaneView
        }
        for subview in rootView.subviews {
            if let paneView = findHostedPaneView(in: subview, paneID: paneID) {
                return paneView
            }
        }

        return nil
    }

    private func focusTarget(for paneView: NSView) -> NSView {
        (paneView as? any WorkspacePaneRendering)?.focusTarget ?? paneView
    }

    func toggleSidebarVisibility() {
        isSidebarVisible.toggle()
        sidebarVisibilityStore.isSidebarVisible = isSidebarVisible
        applySidebarVisibility()
    }

    private func reloadVaultSessions(reset: Bool) {
        guard let vaultStore else {
            return
        }
        if vaultIsLoading && reset == false {
            return
        }
        if reset {
            vaultResultOffset = 0
            vaultHasMore = true
            vaultIsLoading = true
            reloadAvailableVaultAgents()
            if let workspace = currentWorkspace {
                renderVaultSidebar(activeWorkspace: workspace)
            }
        } else if vaultHasMore == false {
            return
        }

        let generation = UUID()
        vaultLoadGeneration = generation
        vaultIsLoading = true
        let offset = vaultResultOffset
        let request = VaultSearchRequest(
            query: vaultSearchQuery,
            agents: vaultAgentFilter.map { [$0] },
            offset: offset,
            limit: vaultSidebarPageSize()
        )
        Task { [weak self] in
            do {
                let response = try await vaultStore.search(request)
                guard let self, self.vaultLoadGeneration == generation else { return }
                let nextSessions: [VaultSessionSummary]
                if offset == 0 {
                    nextSessions = response.sessions
                } else {
                    let knownIDs = Set(self.vaultSessions.map(\.id))
                    nextSessions = self.vaultSessions + response.sessions.filter { knownIDs.contains($0.id) == false }
                }
                self.vaultResultOffset = offset + response.sessions.count
                self.vaultHasMore = self.vaultResultOffset < response.totalCount && response.sessions.isEmpty == false
                self.vaultIsLoading = false
                self.vaultSessions = nextSessions
                if let workspace = self.currentWorkspace {
                    self.renderVaultSidebar(activeWorkspace: workspace)
                }
            } catch {
                if let self, self.vaultLoadGeneration == generation {
                    self.vaultIsLoading = false
                    if let workspace = self.currentWorkspace {
                        self.renderVaultSidebar(activeWorkspace: workspace)
                    }
                }
                fputs("Agent Sessions list failed: \(error)\n", stderr)
            }
        }
    }

    private func renderVaultSidebar(activeWorkspace: Workspace, allWorkspaces providedWorkspaces: [Workspace]? = nil) {
        let allWorkspaces = providedWorkspaces ?? controller.allWorkspaces()
        let normalizedWorkspaceFilter = normalizedVaultWorkspaceFilter(for: allWorkspaces)
        if vaultWorkspaceFilter != normalizedWorkspaceFilter {
            vaultWorkspaceFilter = normalizedWorkspaceFilter
        }
        let scopedVaultSessions = vaultSessions(
            for: normalizedWorkspaceFilter,
            activeWorkspace: activeWorkspace,
            allWorkspaces: allWorkspaces
        )
        pruneActiveVaultSessionBindings(allWorkspaces: allWorkspaces)
        let workspaceFilterItems = vaultWorkspaceFilterItems(activeWorkspace: activeWorkspace, allWorkspaces: allWorkspaces)
        let availableAgents = availableVaultAgents.union(vaultSessions.map(\.agent))
        vaultSidebarView.render(
            sessions: scopedVaultSessions,
            searchQuery: vaultSearchQuery,
            selectedAgent: vaultAgentFilter,
            availableAgents: availableAgents,
            workspaceFilter: normalizedWorkspaceFilter,
            workspaceFilterItems: workspaceFilterItems,
            isLoading: vaultIsLoading,
            hasMore: vaultHasMore,
            sessionActivityByID: [:],
            theme: currentTheme,
            isCollapsed: isAgentSessionsSectionCollapsed,
            isAgentSessionsEnabled: vaultConfiguration.enabled,
            onToggle: { [weak self] in
                self?.toggleVaultSidebar()
            },
            onRefresh: { [weak self] in
                self?.refreshVaultSessions()
            },
            onSearchChanged: { [weak self] query in
                self?.updateVaultSearchQuery(query)
            },
            onAgentFilterChanged: { [weak self] agent in
                self?.updateVaultAgentFilter(agent)
            },
            onWorkspaceFilterChanged: { [weak self] filter in
                self?.updateVaultWorkspaceFilter(filter)
            },
            onNeedsMore: { [weak self] in
                self?.loadMoreVaultSessions()
            },
            onResume: { [weak self] sessionID in
                self?.resumeVaultSession(sessionID)
            },
            onDelete: { [weak self] sessionID in
                self?.deleteVaultSessionPrompt(sessionID: sessionID)
            },
            onToggleCollapse: { [weak self] in
                self?.toggleAgentSessionsCollapsed()
            }
        )
        vaultSidebarView.worktreesWidget.render(
            worktrees: worktrees,
            isCollapsed: isWorktreesSectionCollapsed,
            theme: currentTheme,
            onNavigate: { [weak self] worktree in
                self?.navigateToWorktree(worktree)
            },
            onDelete: { [weak self] worktree in
                self?.deleteWorktreePrompt(worktree)
            },
            onCreate: { [weak self] in
                self?.showCreateWorktreeSheet()
            },
            onRefresh: { [weak self] in
                self?.reloadWorktrees()
            },
            onToggleCollapse: { [weak self] in
                self?.toggleWorktreesCollapsed()
            }
        )
    }

    private func loadMoreVaultSessions() {
        reloadVaultSessions(reset: false)
    }

    private func refreshVaultSessions() {
        guard let vaultStore else {
            reloadVaultSessions(reset: true)
            return
        }
        let agent = vaultAgentFilter
        Task { [weak self] in
            do {
                let warnings = try await vaultStore.reindex(agent: agent)
                for warning in warnings {
                    fputs("Agent Sessions refresh warning: \(warning)\n", stderr)
                }
            } catch {
                fputs("Agent Sessions refresh failed: \(error)\n", stderr)
            }
            guard let self else { return }
            self.reloadVaultSessions(reset: true)
        }
    }

    private func reloadAvailableVaultAgents() {
        guard let vaultStore else {
            return
        }
        let generation = UUID()
        vaultAgentLoadGeneration = generation
        Task { [weak self] in
            let agents: Set<VaultAgentKind>
            do {
                agents = Set(try await vaultStore.availableAgents())
            } catch {
                fputs("Agent Sessions agent availability failed: \(error)\n", stderr)
                agents = []
            }
            guard let self, self.vaultAgentLoadGeneration == generation else { return }
            self.availableVaultAgents = agents
            if let workspace = self.currentWorkspace {
                self.renderVaultSidebar(activeWorkspace: workspace)
            }
        }
    }

    private func updateVaultSearchQuery(_ query: String) {
        guard vaultSearchQuery != query else {
            return
        }
        vaultSearchQuery = query
        reloadVaultSessions(reset: true)
    }

    private func updateVaultAgentFilter(_ agent: VaultAgentKind?) {
        guard vaultAgentFilter != agent else {
            return
        }
        vaultAgentFilter = agent
        reloadVaultSessions(reset: true)
    }

    private func updateVaultWorkspaceFilter(_ filter: VaultWorkspaceFilter) {
        guard vaultWorkspaceFilter != filter else {
            return
        }
        vaultWorkspaceFilter = filter
        if let workspace = currentWorkspace {
            renderVaultSidebar(activeWorkspace: workspace)
        }
    }

    private func resumeVaultSession(_ sessionID: String) {
        guard let vaultStore else {
            return
        }
        Task { [weak self] in
            do {
                guard let snapshot = try await vaultStore.resumeSnapshot(sessionID: sessionID),
                      let command = snapshot.resumeCommand
                else {
                    return
                }
                guard let self else { return }
                let allWorkspaces = self.controller.allWorkspaces()
                let connectedPaths = self.currentWorkspace.map {
                    self.vaultConnectedPaths(for: $0, allWorkspaces: allWorkspaces)
                } ?? []
                let pathMatches = Self.vaultPathMatches(snapshot.workingDirectory, connectedPaths: connectedPaths)
                if pathMatches {
                    self.runVaultResumeCommand(sessionID: sessionID, resumeCommand: command)
                    return
                }
                if snapshot.kind == .codex {
                    self.runVaultResumeCommand(sessionID: sessionID, resumeCommand: command)
                    return
                }

                self.presentVaultResumeMismatchModal(
                    sessionID: sessionID,
                    resumeCommand: command,
                    workingDirectory: snapshot.workingDirectory,
                    connectedPaths: connectedPaths
                )
            } catch {
                fputs("Agent Sessions resume failed: \(error)\n", stderr)
            }
        }
    }

    private func presentVaultResumeMismatchModal(
        sessionID: String,
        resumeCommand: String,
        workingDirectory: String?,
        connectedPaths: [String]
    ) {
        let modal = AgentSessionPathMismatchModalView(
            workingDirectory: workingDirectory,
            connectedPaths: connectedPaths,
            theme: currentTheme
        )
        modal.onChoice = { [weak self, weak modal] choice in
            guard let self else { return }
            if let modal {
                self.shellOverlayHostView.dismiss(agentSessionPathMismatchView: modal)
            }
            switch choice {
            case .resumeHere:
                self.runVaultResumeCommand(sessionID: sessionID, resumeCommand: resumeCommand)
            case .openWorkspace:
                if let workingDirectory {
                    self.runVaultResumeCommand(
                        sessionID: sessionID,
                        resumeCommand: resumeCommand,
                        openWorkspaceAt: workingDirectory
                    )
                }
            case .cancel:
                break
            }
        }
        shellOverlayHostView.present(agentSessionPathMismatchView: modal)
    }

    func presentWorkspaceRestoreBanner(_ entry: RecentlyClosedWorkspaceEntry, controller: WorkspaceController) {
        let bannerView = WorkspaceRestoreBannerView(entry: entry, theme: currentTheme)
        bannerView.onChoice = { [weak self, weak bannerView] choice in
            guard let self else {
                return
            }
            if let bannerView {
                self.shellOverlayHostView.dismiss(workspaceRestoreBannerView: bannerView)
            }

            switch choice {
            case .cancel:
                break
            case .restoreHere:
                do {
                    _ = try controller.restoreClosedWorkspaceInActiveWorkspace(entry)
                    controller.removeRecentlyClosedWorkspace(byID: entry.id)
                } catch {
                    try? controller.notify(
                        NotificationRequest(
                            title: "Restore failed",
                            body: error.localizedDescription,
                            severity: .error
                        )
                    )
                }
            case .restoreAsNewWorkspace:
                do {
                    _ = try controller.reopenClosedWorkspace(entry)
                    controller.removeRecentlyClosedWorkspace(byID: entry.id)
                } catch {
                    try? controller.notify(
                        NotificationRequest(
                            title: "Restore failed",
                            body: error.localizedDescription,
                            severity: .error
                        )
                    )
                }
            }
        }
        shellOverlayHostView.present(workspaceRestoreBannerView: bannerView)
    }

    private func dismissIrrelevantRestoreBanners(for workspace: Workspace) {
        let relevantRoots = restoreBannerRelevantRoots(for: workspace)
        guard relevantRoots.isEmpty == false else {
            return
        }

        shellOverlayHostView.dismissWorkspaceRestoreBanners { bannerView in
            let bannerRoots = Self.restoreBannerRoots(for: bannerView.entry.workspacePaths)
            return bannerRoots.isDisjoint(with: relevantRoots)
        }
    }

    private func restoreBannerRelevantRoots(for workspace: Workspace) -> Set<String> {
        Self.restoreBannerRoots(for: vaultConnectedPaths(for: workspace, allWorkspaces: controller.allWorkspaces()))
    }

    private static func restoreBannerRoots(for paths: [String]) -> Set<String> {
        Set(paths.compactMap(Self.standardizedVaultPath))
    }

    private func runVaultResumeCommand(
        sessionID: String,
        resumeCommand: String,
        openWorkspaceAt workingDirectory: String? = nil
    ) {
        if let workingDirectory {
            _ = try? controller.openWorkspace(at: workingDirectory)
        }
        guard let result = try? controller.runCommand(target: .focused, command: resumeCommand),
              let paneID = result.target?.paneID
        else {
            return
        }
        activeVaultSessionByPaneID[paneID] = sessionID
        if let workspace = currentWorkspace {
            renderVaultSidebar(activeWorkspace: workspace)
        }
    }

    private func activePaneID(forVaultSession sessionID: String, allWorkspaces: [Workspace], sessions: [VaultSessionSummary]) -> PaneID? {
        activeVaultSessionBindings(allWorkspaces: allWorkspaces, sessions: sessions).first { _, activeSessionID in
            activeSessionID == sessionID
        }?.key
    }

    private func pruneActiveVaultSessionBindings(allWorkspaces: [Workspace]) {
        let validPaneIDs = Set(
            allWorkspaces.flatMap { workspace in
                workspace.tabs.flatMap { $0.panes.map(\.id) }
            }
        )
        activeVaultSessionByPaneID = activeVaultSessionByPaneID.filter { validPaneIDs.contains($0.key) }
    }

    private func activeVaultSessionBindings(allWorkspaces: [Workspace], sessions: [VaultSessionSummary]) -> [PaneID: String] {
        let panes = allVaultActivityPanes(in: allWorkspaces)
        let validPaneIDs = Set(panes.map(\.id))
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let activeExplicitBindings = activeVaultSessionByPaneID.filter { paneID, sessionID in
            guard validPaneIDs.contains(paneID),
                  let pane = panes.first(where: { $0.id == paneID }),
                  let session = sessionByID[sessionID]
            else {
                return false
            }
            if let agent = Self.inferredVaultAgentKind(for: pane) {
                return agent == session.agent
            }
            return true
        }
        activeVaultSessionByPaneID = activeExplicitBindings
        return activeExplicitBindings
    }

    private func allVaultActivityPanes(in workspaces: [Workspace]) -> [Pane] {
        workspaces.flatMap { workspace in
            workspace.tabs.flatMap(\.panes) + workspace.floatingPaneModals.flatMap(\.panes)
        }
    }

    private func deleteVaultSessionPrompt(sessionID: String) {
        presentConfirmation(
            title: "Delete Agent Session",
            message: "This removes the indexed session from OpenMUX.",
            actionTitle: "Delete"
        ) { [weak self] in
            self?.deleteVaultSession(sessionID: sessionID)
        }
    }

    private func deleteVaultSession(sessionID: String) {
        guard let vaultStore else {
            return
        }
        Task { [weak self] in
            do {
                try await vaultStore.delete(sessionID: sessionID)
                guard let self else { return }
                self.activeVaultSessionByPaneID = self.activeVaultSessionByPaneID.filter { $0.value != sessionID }
                self.reloadVaultSessions(reset: true)
                self.reloadAvailableVaultAgents()
            } catch {
                fputs("Agent Sessions delete failed: \(error)\n", stderr)
            }
        }
    }

    private func applySidebarVisibility() {
        sidebarView.isHidden = !isSidebarVisible
        sidebarWidthConstraint?.constant = isSidebarVisible ? ShellLayoutMetrics.sidebarWidth : 0
        mainColumnLeadingConstraint?.constant = isSidebarVisible ? ShellLayoutMetrics.interRegionSpacing : 0
        view.layoutSubtreeIfNeeded()
    }

    @objc private func toggleSidebarPressed() {
        toggleSidebarVisibility()
    }

    @objc private func toggleVaultSidebarPressed() {
        toggleVaultSidebar()
    }

    func toggleVaultSidebar() {
        isVaultSidebarVisible.toggle()
        applyVaultSidebarVisibility()
        if isVaultSidebarVisible, vaultSessions.isEmpty, vaultIsLoading == false {
            reloadVaultSessions(reset: true)
        }
    }

    func toggleAgentSessionsPanel() {
        if isVaultSidebarVisible == false, vaultSessions.isEmpty, vaultIsLoading == false {
            reloadVaultSessions(reset: true)
        }
        toggleSidebarPanel(panelID: "agentSessions", isCollapsed: isAgentSessionsSectionCollapsed)
    }

    func toggleWorktreesPanel() {
        toggleSidebarPanel(panelID: "worktrees", isCollapsed: isWorktreesSectionCollapsed)
    }

    /// Opens the sidebar that owns `panelID` (if closed) and toggles the panel's collapsed state.
    ///
    /// - If the sidebar is closed: opens it and expands the panel if it was collapsed.
    /// - If the sidebar is open and the panel is collapsed: expands it.
    /// - If the sidebar is open and the panel is expanded: collapses it.
    private func toggleSidebarPanel(panelID: String, isCollapsed: Bool) {
        let side = sidebarSide(owning: panelID) ?? "right"
        let sidebarOpen = (side == "left") ? isSidebarVisible : isVaultSidebarVisible

        if !sidebarOpen {
            ensureSidebarVisible(owning: panelID)
            if isCollapsed {
                setPanelCollapsed(panelID: panelID, isCollapsed: false)
            }
        } else if isCollapsed {
            setPanelCollapsed(panelID: panelID, isCollapsed: false)
        } else {
            setPanelCollapsed(panelID: panelID, isCollapsed: true)
        }
    }

    func setVaultSidebarVisibility(_ isVisible: Bool) {
        guard isVaultSidebarVisible != isVisible else {
            return
        }
        isVaultSidebarVisible = isVisible
        applyVaultSidebarVisibility()
        if isVaultSidebarVisible, vaultSessions.isEmpty, vaultIsLoading == false {
            reloadVaultSessions(reset: true)
        }
    }

    // MARK: - Worktrees

    /// Subscribes to `commandFinished` terminal events on the `WorkspaceController`
    /// so that manual `git worktree` CLI commands refresh the widget immediately.
    private func subscribeToCommandFinished() {
        let previous = controller.onTerminalEvent
        controller.onTerminalEvent = { [weak self] event in
            previous?(event)
            guard event.name == ControlPlaneTerminalEventName.commandFinished.rawValue else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      let focusedPaneID = self.currentWorkspace?.focusedPane?.id,
                      event.paneID == focusedPaneID else { return }
                self.reloadWorktrees()
            }
        }
    }

    private func reloadWorktrees() {
        guard let cwd = currentWorkspace?.focusedPane?.terminalSession?.workingDirectory else {
            worktrees = []
            if let workspace = currentWorkspace { update(workspace: workspace) }
            return
        }
        let directory = cwd
        Task.detached(priority: .userInitiated) { [weak self] in
            let list = GitWorktreeResolver.listWorktrees(in: directory)
            let branches = GitWorktreeResolver.listBranches(in: directory)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.worktrees = list
                self.worktreeBranches = branches
                if let workspace = self.currentWorkspace {
                    self.update(workspace: workspace)
                }
            }
        }
    }

    private func navigateToWorktree(_ worktree: GitWorktree) {
        let path = worktree.path
        let escaped = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        _ = try? controller.runCommand(target: .focused, command: "cd \(escaped)")
        controller.setPaneWorkingDirectory(target: .focused, path: path)
    }

    private func deleteWorktreePrompt(_ worktree: GitWorktree) {
        presentConfirmation(
            title: "Remove Worktree",
            message: "This will remove the worktree at \(worktree.path). The branch will not be deleted.",
            actionTitle: "Remove"
        ) { [weak self] in
            self?.deleteWorktree(worktree)
        }
    }

    private func deleteWorktree(_ worktree: GitWorktree) {
        guard let cwd = currentWorkspace?.focusedPane?.terminalSession?.workingDirectory else { return }
        let directory = cwd
        let path = worktree.path
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = GitWorktreeResolver.removeWorktree(at: path, in: directory)
            await MainActor.run { [weak self] in
                self?.reloadWorktrees()
            }
        }
    }

    private func showCreateWorktreeSheet() {
        guard let cwd = currentWorkspace?.focusedPane?.terminalSession?.workingDirectory else { return }
        showCreateWorktreeSheet(repoDirectory: cwd, branches: worktreeBranches) { [weak self] branch, fromRef in
            self?.createWorktree(branch: branch, fromRef: fromRef, repoDirectory: cwd)
        }
    }

    private func showCreateWorktreeSheet(
        repoDirectory: String,
        branches: [String],
        onConfirm: @escaping (String, String?) -> Void
    ) {
        let defaultBranch = "worktree/\(UUID().uuidString.prefix(8).lowercased())"

        let branchLabel = NSTextField(labelWithString: "New branch name:")
        branchLabel.font = .systemFont(ofSize: 12)
        branchLabel.frame = NSRect(x: 0, y: 96, width: 300, height: 16)

        let branchField = NSTextField()
        branchField.stringValue = defaultBranch
        branchField.font = .systemFont(ofSize: 13)
        branchField.frame = NSRect(x: 0, y: 64, width: 300, height: 24)

        let fromLabel = NSTextField(labelWithString: "Base branch:")
        fromLabel.font = .systemFont(ofSize: 12)
        fromLabel.frame = NSRect(x: 0, y: 36, width: 300, height: 16)

        let fromPopup = NSPopUpButton()
        fromPopup.addItem(withTitle: "(current HEAD)")
        for b in branches { fromPopup.addItem(withTitle: b) }
        fromPopup.frame = NSRect(x: 0, y: 0, width: 300, height: 26)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 130))
        accessory.addSubview(branchLabel)
        accessory.addSubview(branchField)
        accessory.addSubview(fromLabel)
        accessory.addSubview(fromPopup)

        presentConfirmation(
            title: "Create Worktree",
            actionTitle: "Create",
            alertStyle: .informational,
            accessoryView: accessory
        ) {
            let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard branch.isEmpty == false else { return }
            let fromRef: String? = fromPopup.indexOfSelectedItem == 0 ? nil : fromPopup.titleOfSelectedItem
            onConfirm(branch, fromRef)
        }
    }

    private func createWorktree(branch: String, fromRef: String?, repoDirectory: String) {
        let path = GitWorktreeResolver.defaultWorktreePath(branch: branch, in: repoDirectory)
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = GitWorktreeResolver.addWorktree(branch: branch, fromRef: fromRef, at: path, in: repoDirectory)
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    let worktree = GitWorktree(path: path, branch: branch, isMainWorktree: false, isCurrentRepo: false)
                    self.navigateToWorktree(worktree)
                    self.reloadWorktrees()
                case .failure(let error):
                    fputs("Create worktree failed: \(error)\n", stderr)
                }
            }
        }
    }

    /// Returns whichever split view currently owns the panel with the given ID.
    private func splitView(owning panelID: String) -> SidebarSplitView? {
        if sidebarView.splitView.panelIDs.contains(panelID) { return sidebarView.splitView }
        if vaultSidebarView.splitView.panelIDs.contains(panelID) { return vaultSidebarView.splitView }
        return nil
    }

    /// Returns "left" or "right" depending on which sidebar currently owns the panel.
    private func sidebarSide(owning panelID: String) -> String? {
        if sidebarView.splitView.panelIDs.contains(panelID) { return "left" }
        if vaultSidebarView.splitView.panelIDs.contains(panelID) { return "right" }
        return nil
    }

    /// Ensures the sidebar that owns `panelID` is visible. Returns false if the panel
    /// cannot be found (caller should fall back to opening the default sidebar).
    @discardableResult
    private func ensureSidebarVisible(owning panelID: String) -> Bool {
        guard let side = sidebarSide(owning: panelID) else { return false }
        if side == "left" {
            guard !isSidebarVisible else { return true }
            isSidebarVisible = true
            sidebarVisibilityStore.isSidebarVisible = true
            applySidebarVisibility()
        } else {
            guard !isVaultSidebarVisible else { return true }
            isVaultSidebarVisible = true
            applyVaultSidebarVisibility()
        }
        return true
    }

    private func toggleWorktreesCollapsed() {
        setPanelCollapsed(panelID: "worktrees", isCollapsed: !isWorktreesSectionCollapsed)
    }

    private func toggleAgentSessionsCollapsed() {
        setPanelCollapsed(panelID: "agentSessions", isCollapsed: !isAgentSessionsSectionCollapsed)
    }

    private func toggleWorkspacesCollapsed() {
        setPanelCollapsed(panelID: "workspaces", isCollapsed: !isWorkspacesSectionCollapsed)
    }

    /// Sets the collapsed state of a sidebar panel and persists the new value.
    private func setPanelCollapsed(panelID: String, isCollapsed: Bool) {
        switch panelID {
        case "worktrees":
            isWorktreesSectionCollapsed = isCollapsed
        case "agentSessions":
            isAgentSessionsSectionCollapsed = isCollapsed
        case "workspaces":
            isWorkspacesSectionCollapsed = isCollapsed
        default:
            return
        }
        let side = sidebarSide(owning: panelID) ?? "right"
        UserDefaults.standard.set(isCollapsed, forKey: "omux.\(side)Sidebar.\(panelID)Collapsed")
        splitView(owning: panelID)?.setCollapsed(isCollapsed, panelID: panelID)
        if let workspace = currentWorkspace { update(workspace: workspace) }
    }

    private func persistSidebarPanelOrder() {
        let leftOrder = sidebarView.splitView.panelIDs
        let rightOrder = vaultSidebarView.splitView.panelIDs
        UserDefaults.standard.set(leftOrder, forKey: "omux.leftSidebar.panelOrder")
        UserDefaults.standard.set(rightOrder, forKey: "omux.rightSidebar.panelOrder")
        for panelID in leftOrder {
            persistPanelCollapsedState(panelID: panelID, sidebarNamespace: "omux.leftSidebar")
        }
        for panelID in rightOrder {
            persistPanelCollapsedState(panelID: panelID, sidebarNamespace: "omux.rightSidebar")
        }
    }

    private func configureSidebarPanelsFromDefaults() {
        let orders = restoredSidebarPanelOrders()
        sidebarView.splitView.setPanels([])
        vaultSidebarView.splitView.setPanels([])

        isWorkspacesSectionCollapsed = panelCollapsedState(
            panelID: "workspaces",
            sidebarNamespace: orders.left.contains("workspaces") ? "omux.leftSidebar" : "omux.rightSidebar"
        )
        isWorktreesSectionCollapsed = panelCollapsedState(
            panelID: "worktrees",
            sidebarNamespace: orders.left.contains("worktrees") ? "omux.leftSidebar" : "omux.rightSidebar"
        )
        isAgentSessionsSectionCollapsed = panelCollapsedState(
            panelID: "agentSessions",
            sidebarNamespace: orders.left.contains("agentSessions") ? "omux.leftSidebar" : "omux.rightSidebar"
        )

        sidebarView.splitView.setPanels(orders.left.compactMap { panel(for: $0, sidebarNamespace: "omux.leftSidebar") })
        vaultSidebarView.splitView.setPanels(orders.right.compactMap { panel(for: $0, sidebarNamespace: "omux.rightSidebar") })
    }

    private func restoredSidebarPanelOrders() -> (left: [String], right: [String]) {
        let defaultLeft = ["workspaces"]
        let defaultRight = ["worktrees", "agentSessions"]
        let knownPanels = Set(defaultLeft + defaultRight)
        let hasSavedLeft = UserDefaults.standard.object(forKey: "omux.leftSidebar.panelOrder") != nil
        let hasSavedRight = UserDefaults.standard.object(forKey: "omux.rightSidebar.panelOrder") != nil
        guard hasSavedLeft || hasSavedRight else {
            return (defaultLeft, defaultRight)
        }

        var seen = Set<String>()
        func sanitized(_ raw: [String]) -> [String] {
            raw.compactMap { panelID in
                guard knownPanels.contains(panelID), seen.insert(panelID).inserted else {
                    return nil
                }
                return panelID
            }
        }

        var left = sanitized(UserDefaults.standard.stringArray(forKey: "omux.leftSidebar.panelOrder") ?? defaultLeft)
        var right = sanitized(UserDefaults.standard.stringArray(forKey: "omux.rightSidebar.panelOrder") ?? defaultRight)
        for panelID in defaultLeft where seen.insert(panelID).inserted {
            left.append(panelID)
        }
        for panelID in defaultRight where seen.insert(panelID).inserted {
            right.append(panelID)
        }
        return (left, right)
    }

    private func panel(for panelID: String, sidebarNamespace: String) -> SidebarSplitView.Panel? {
        switch panelID {
        case "workspaces":
            return sidebarView.makeWorkspacesPanel(sidebarNamespace: sidebarNamespace)
        case "worktrees":
            return vaultSidebarView.makeWorktreesPanel(sidebarNamespace: sidebarNamespace)
        case "agentSessions":
            return vaultSidebarView.makeAgentSessionsPanel(sidebarNamespace: sidebarNamespace)
        default:
            return nil
        }
    }

    private func panelCollapsedState(panelID: String, sidebarNamespace: String) -> Bool {
        UserDefaults.standard.bool(forKey: "\(sidebarNamespace).\(panelID)Collapsed")
    }

    private func persistPanelCollapsedState(panelID: String, sidebarNamespace: String) {
        let collapsed: Bool
        switch panelID {
        case "workspaces":
            collapsed = isWorkspacesSectionCollapsed
        case "worktrees":
            collapsed = isWorktreesSectionCollapsed
        case "agentSessions":
            collapsed = isAgentSessionsSectionCollapsed
        default:
            return
        }
        UserDefaults.standard.set(collapsed, forKey: "\(sidebarNamespace).\(panelID)Collapsed")
    }

    private func applyVaultSidebarVisibility() {
        let isVisible = isVaultSidebarVisible
        vaultSidebarView.isHidden = !isVisible
        vaultToggleButton.isHidden = !vaultConfiguration.collapsedToggleVisible
        vaultToggleButton.contentTintColor = currentTheme.shell.textMuted
        vaultSidebarWidthConstraint?.constant = isVisible ? ShellLayoutMetrics.vaultSidebarWidth : 0
        mainColumnTrailingConstraint?.constant = isVisible
            ? -ShellLayoutMetrics.interRegionSpacing
            : -ShellLayoutMetrics.outerPadding - reservedWidthForCollapsedVaultToggle
        view.layoutSubtreeIfNeeded()
    }

    private var reservedWidthForCollapsedVaultToggle: CGFloat {
        // The vault toggle button now lives in the title bar area, so no
        // horizontal space needs to be reserved in the main canvas column.
        return 0
    }

    private func configureVaultSourceIndexing() {
        guard vaultConfiguration.enabled, let vaultStore else {
            return
        }

        let coordinator = VaultIndexRefreshCoordinator(vaultStore: vaultStore) { [weak self] _ in
            self?.vaultIndexDidUpdate()
        }
        let sources = VaultWatchSourceFactory.sources(configuration: vaultConfiguration)
        guard sources.isEmpty == false else {
            vaultIndexRefreshCoordinator = coordinator
            return
        }
        let watcher = VaultSourceEventWatcher(sources: sources) { [weak coordinator] agent in
            coordinator?.markDirty(agent)
        }
        watcher.start()
        vaultIndexRefreshCoordinator = coordinator
        vaultSourceEventWatcher = watcher
    }

    func vaultIndexDidUpdate() {
        guard isVaultSidebarVisible else {
            return
        }
        reloadAvailableVaultAgents()
        reloadVaultSessions(reset: true)
    }

    private func vaultSessions(
        for filter: VaultWorkspaceFilter,
        activeWorkspace: Workspace,
        allWorkspaces: [Workspace]
    ) -> [VaultSessionSummary] {
        switch filter {
        case .all:
            return vaultSessions
        case .current:
            let connectedPaths = vaultConnectedPaths(for: activeWorkspace, allWorkspaces: allWorkspaces)
            return vaultSessions.filter {
                Self.vaultPathMatches($0.workingDirectory, connectedPaths: connectedPaths)
            }
        case .workspace(let workspaceID):
            guard let workspace = allWorkspaces.first(where: { $0.id == workspaceID }) else {
                let connectedPaths = vaultConnectedPaths(for: activeWorkspace, allWorkspaces: allWorkspaces)
                return vaultSessions.filter {
                    Self.vaultPathMatches($0.workingDirectory, connectedPaths: connectedPaths)
                }
            }

            let connectedPaths = vaultConnectedPaths(for: workspace, allWorkspaces: allWorkspaces)
            return vaultSessions.filter {
                Self.vaultPathMatches($0.workingDirectory, connectedPaths: connectedPaths)
            }
        }
    }

    private func vaultSidebarPageSize() -> Int {
        let agentCount: Int
        if vaultAgentFilter != nil {
            agentCount = 1
        } else {
            let configuredAgentCount = vaultConfiguration.includedAgents.filter { $0 != .custom }.count
            let visibleAgentCount = availableVaultAgents.filter { $0 != .custom }.count
            agentCount = max(1, configuredAgentCount, visibleAgentCount)
        }
        return min(500, max(1, vaultConfiguration.sidebarRowsPerAgent) * agentCount)
    }

    private func normalizedVaultWorkspaceFilter(for allWorkspaces: [Workspace]) -> VaultWorkspaceFilter {
        guard case .workspace(let workspaceID) = vaultWorkspaceFilter,
              allWorkspaces.contains(where: { $0.id == workspaceID }) == false
        else {
            return vaultWorkspaceFilter
        }
        return .current
    }

    private func vaultWorkspaceFilterItems(
        activeWorkspace: Workspace,
        allWorkspaces: [Workspace]
    ) -> [WorkspaceVaultSidebarView.WorkspaceFilterItem] {
        var items: [WorkspaceVaultSidebarView.WorkspaceFilterItem] = [
            .init(title: "Current workspace", filter: .current),
            .init(title: "All workspaces", filter: .all),
        ]
        items += allWorkspaces.map { workspace in
            let title = workspace.id == activeWorkspace.id ? "\(workspace.name) (active)" : workspace.name
            return WorkspaceVaultSidebarView.WorkspaceFilterItem(title: title, filter: .workspace(workspace.id))
        }
        return items
    }

    private func vaultConnectedPaths(for workspace: Workspace, allWorkspaces: [Workspace]) -> [String] {
        let panes = workspace.tabs.flatMap(\.panes) + workspace.floatingPaneModals.flatMap(\.panes)
        let panePaths = panes.compactMap { pane in controller.workingDirectory(for: pane.id) }

        return Self.vaultConnectedPaths(
            for: workspace,
            allWorkspaces: allWorkspaces,
            panePaths: panePaths
        )
    }

    static func vaultConnectedPaths(
        for workspace: Workspace,
        allWorkspaces: [Workspace],
        panePaths: [String]
    ) -> [String] {
        let standardizedPanePaths = panePaths.compactMap(WorkspaceRootPathCalculator.standardizedPath)
        if let commonRootPath = WorkspaceRootPathCalculator.highestCommonPath(for: standardizedPanePaths) {
            return [commonRootPath]
        }

        if workspace.rootPathMode == .manual,
           let manualRootPath = WorkspaceRootPathCalculator.standardizedPath(workspace.rootPath) {
            return [manualRootPath]
        }

        return Self.fallbackVaultRootPath(for: workspace, allWorkspaces: allWorkspaces)
            .map { [$0] } ?? []
    }

    private static func fallbackVaultRootPath(
        for workspace: Workspace,
        allWorkspaces: [Workspace]
    ) -> String? {
        guard let rootPath = WorkspaceRootPathCalculator.standardizedPath(workspace.rootPath) else {
            return nil
        }

        let siblingRoots = allWorkspaces
            .filter { $0.id != workspace.id }
            .compactMap { WorkspaceRootPathCalculator.standardizedPath($0.rootPath) }
        let isOverlyBroadFallback = siblingRoots.contains { siblingRoot in
            siblingRoot == rootPath || siblingRoot.hasPrefix(rootPath + "/")
        }

        return isOverlyBroadFallback ? nil : rootPath
    }

    private static func vaultPathMatches(_ candidate: String?, connectedPaths: [String]) -> Bool {
        guard let candidate = candidate.flatMap(standardizedVaultPath) else {
            return false
        }
        return connectedPaths.contains { connectedPath in
            candidate == connectedPath
                || candidate.hasPrefix(connectedPath + "/")
        }
    }

    private static func vaultPathsOverlap(_ sessionPath: String?, _ panePath: String?) -> Bool {
        guard let sessionPath = sessionPath.flatMap(standardizedVaultPath),
              let panePath = panePath.flatMap(standardizedVaultPath)
        else {
            return false
        }
        return sessionPath == panePath
            || sessionPath.hasPrefix(panePath + "/")
            || panePath.hasPrefix(sessionPath + "/")
    }

    private static func currentVaultPath(for pane: Pane) -> String? {
        pane.terminalState.reportedWorkingDirectory
            ?? pane.terminalSession?.workingDirectory
    }

    private static func inferredVaultAgentKind(for pane: Pane) -> VaultAgentKind? {
        if let adapterID = pane.terminalState.agentStatusAdapterID,
           let agent = VaultAgentKind(rawValue: adapterID) {
            return agent
        }

        let titleCandidates = [
            pane.terminalState.reportedTitle,
            pane.title,
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        for title in titleCandidates where title.isEmpty == false {
            if let observed = OmuxAIStatusTitleObserver.observe(title: title),
               let agent = VaultAgentKind(rawValue: observed.adapterID) {
                return agent
            }

            let normalized = title.localizedLowercase
            if normalized.contains("github copilot") || normalized.contains("copilot") {
                return .copilot
            }
            if normalized.contains("codex") {
                return .codex
            }
            if normalized.contains("gemini") {
                return .gemini
            }
        }

        return nil
    }

    private static func standardizedVaultPath(_ path: String) -> String? {
        WorkspaceRootPathCalculator.standardizedPath(path)
    }

    private func makeWorkspaceSidebarItems(
        workspaces: [Workspace],
        activeWorkspace: Workspace,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?
    ) -> [SidebarItem] {
        return workspaces.flatMap { workspace in
            let panes = workspace.tabs.flatMap(\.panes)
            let isExpanded = collapsedWorkspaceIDs.contains(workspace.id) == false
            let workspaceItem = SidebarItem(
                kind: .workspace,
                identifier: workspace.id.rawValue,
                icon: renderedIcon(
                    for: iconResolver.icon(
                        for: panes,
                        focusedPaneID: workspace.focusedPane?.id,
                        terminalText: terminalTextProvider
                    ),
                    pointSize: 13,
                    weight: .semibold
                ),
                progress: nil,
                title: workspace.name,
                subtitle: nil,
                isActive: workspace.id == activeWorkspace.id,
                isExpanded: isExpanded,
                action: .workspace(workspace.id),
                contextMenuProvider: { [weak self] in
                    guard let self else { return NSMenu() }
                    return makeWorkspaceContextMenu(for: workspace, onBeginRename: nil)
                }
            )

            let terminalItems = isExpanded ? workspace.tabs
                .flatMap { tab in
                    tab.panes.map { pane -> SidebarItem in
                        let paneIcon = iconResolver.icon(for: pane, terminalText: terminalTextProvider(pane))
                        let metadata = metadataResolver.metadata(for: pane, icon: paneIcon)
                        let paneStack = tab.rootLayout.paneStack(containingPaneID: pane.id)
                        let rows = resolvedSidebarRows(for: pane, metadata: metadata)
                        let title = rows.row1 ?? metadata.title
                        let subtitle = rows.row2
                        let detail = rows.row3
                        let subtitleAccentPrefixLength: Int? = {
                            guard metadata.isWorktree,
                                  let branch = metadata.gitBranch,
                                  let subtitle,
                                  subtitle.hasPrefix(branch)
                            else {
                                return nil
                            }
                            return branch.utf16.count
                        }()
                        return SidebarItem(
                            kind: .terminal,
                            identifier: pane.id.rawValue,
                            icon: renderedIcon(for: metadata.icon, pointSize: 11, weight: .medium),
                            progress: pane.terminalState.progress,
                            title: title,
                            subtitle: subtitle,
                            detail: detail,
                            subtitleAccentPrefixLength: subtitleAccentPrefixLength,
                            isActive: workspace.id == activeWorkspace.id && pane.id == activeWorkspace.focusedPane?.id,
                            isExpanded: nil,
                            action: .pane(pane.id),
                            contextMenuProvider: { [weak self] in
                                guard let self, let paneStack else { return NSMenu() }
                                return makePaneTabContextMenu(
                                    pane: pane,
                                    paneStack: paneStack,
                                    canCloseSinglePaneStack: tab.panes.count > 1 || workspace.tabs.count > 1
                                )
                            }
                        )
                    }
                } : []

            return [workspaceItem] + terminalItems
        }
    }

    private func resolvedSidebarRows(for pane: Pane, metadata: TerminalSidebarMetadata) -> SidebarRowValues {
        let configuredRows = currentSidebar.terminalRows
        var resolvedRows: [String?] = [
            sidebarRowValue(for: configuredRows.row1, metadata: metadata),
            sidebarRowValue(for: configuredRows.row2, metadata: metadata),
            sidebarRowValue(for: configuredRows.row3, metadata: metadata),
        ]
        if let override = paneMetadataRowsOverridesByPaneID[pane.id] {
            if let row1 = override.row1 {
                resolvedRows[0] = row1
            }
            if let row2 = override.row2 {
                resolvedRows[1] = row2
            }
            if let row3 = override.row3 {
                resolvedRows[2] = row3
            }
        }

        let compactRows = resolvedRows.map { value -> String? in
            guard let value else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return SidebarRowValues(
            row1: compactRows[0],
            row2: compactRows[1],
            row3: compactRows[2]
        )
    }

    private func sidebarRowValue(
        for source: OmuxConfigUI.Sidebar.TerminalRowSource,
        metadata: TerminalSidebarMetadata
    ) -> String? {
        switch source {
        case .title:
            return metadata.title
        case .subtitle:
            return metadata.subtitle
        case .path:
            return metadata.path
        case .abbreviatedPath:
            return metadata.abbreviatedPath
        case .gitBranch:
            return metadata.gitBranch
        case .none:
            return nil
        }
    }

    private func toggleWorkspaceExpansion(_ workspaceID: WorkspaceID) {
        if collapsedWorkspaceIDs.contains(workspaceID) {
            collapsedWorkspaceIDs.remove(workspaceID)
        } else {
            collapsedWorkspaceIDs.insert(workspaceID)
        }

        if let workspace = currentWorkspace {
            update(workspace: workspace)
        }
    }

    private func terminalScreenText(for pane: Pane) -> String? {
        guard pane.isTerminal else {
            return nil
        }
        let snapshot = controller.terminalBridge.terminalTextSnapshot(
            for: pane.id,
            maxBytes: 4_096,
            maxLines: 40
        )
        return snapshot.text.isEmpty ? nil : snapshot.text
    }

    private func iconKindSignature(
        for workspace: Workspace,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?
    ) -> [PaneID: OmuxSemanticIcon.Kind] {
        Dictionary(
            uniqueKeysWithValues: workspace.tabs
                .flatMap(\.panes)
                .map { pane in
                    (
                        pane.id,
                        iconResolver.icon(for: pane, terminalText: terminalTextProvider(pane)).kind
                    )
                }
        )
    }

    private func startTerminalIconRefreshTimer() {
        terminalIconRefreshTimer?.invalidate()
        terminalIconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTerminalAppIconsIfNeeded()
            }
        }
    }

    private func refreshTerminalAppIconsIfNeeded() {
        guard let currentWorkspace else {
            return
        }

        let terminalTextCache = TerminalTextRenderCache()
        let terminalTextProvider: @MainActor (Pane) -> String? = { [weak self] pane in
            guard let self else {
                return nil
            }
            return terminalTextCache.text(for: pane) {
                self.terminalScreenText(for: pane)
            }
        }
        let currentSignature = iconKindSignature(
            for: currentWorkspace,
            terminalTextProvider: terminalTextProvider
        )
        guard currentSignature != renderedIconKindByPaneID else {
            return
        }

        update(workspace: currentWorkspace)
    }

    private func renderedIcon(
        for icon: OmuxSemanticIcon,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) -> OmuxRenderedIcon? {
        OmuxIconRenderer(
            configuration: currentIcons,
            pointSize: pointSize,
            weight: weight
        ).render(icon)
    }

    func presentRenameWorkspacePrompt(workspaceID: WorkspaceID? = nil) {
        guard let workspace = workspaceID.flatMap({ id in
            controller.allWorkspaces().first(where: { $0.id == id })
        }) ?? controller.activeWorkspace() else {
            return
        }

        let nameField = NSTextField(string: workspace.customName ?? workspace.name)
        nameField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)

        presentConfirmation(
            title: "Rename Workspace",
            message: "Choose a new name for this workspace.",
            actionTitle: "Rename",
            alertStyle: .informational,
            accessoryView: nameField
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try controller.renameWorkspace(workspace.id, to: nameField.stringValue)
            } catch {
                assertionFailure("Failed to rename workspace: \(error)")
            }
        }
    }

    func presentWorkspaceRootPrompt(workspaceID: WorkspaceID? = nil) {
        guard let workspace = workspaceID.flatMap({ id in
            controller.allWorkspaces().first(where: { $0.id == id })
        }) ?? controller.activeWorkspace() else {
            return
        }

        let pathField = NSTextField(string: workspace.rootPath)
        pathField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)

        let modeDescription = workspace.rootPathMode == .manual
            ? "This workspace currently uses a manual root."
            : "This workspace currently derives its root automatically."
        presentConfirmation(
            title: "Set Workspace Root",
            message: "\(modeDescription) Enter the path OpenMUX should use for new tabs, hooks, and Agent Session filtering.",
            actionTitle: "Set Root",
            alertStyle: .informational,
            accessoryView: pathField
        ) { [weak self] in
            guard let self else { return }
            do {
                _ = try controller.setWorkspaceRootPath(workspace.id, to: pathField.stringValue)
            } catch {
                notifyWorkspaceRootChangeFailure(
                    title: "Set workspace root failed",
                    workspace: workspace,
                    path: pathField.stringValue,
                    error: error
                )
            }
        }
    }

    func resetWorkspaceRootToAutomatic(workspaceID: WorkspaceID? = nil) {
        guard let workspace = workspaceID.flatMap({ id in
            controller.allWorkspaces().first(where: { $0.id == id })
        }) ?? controller.activeWorkspace() else {
            return
        }

        do {
            _ = try controller.resetWorkspaceRootPath(workspace.id)
        } catch {
            notifyWorkspaceRootChangeFailure(
                title: "Reset workspace root failed",
                workspace: workspace,
                path: workspace.rootPath,
                error: error
            )
        }
    }

    private func notifyWorkspaceRootChangeFailure(
        title: String,
        workspace: Workspace,
        path: String,
        error: Error
    ) {
        let resolvedPath = path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? workspace.rootPath : path
        try? controller.notify(
            NotificationRequest(
                title: title,
                body: "Workspace \(workspace.id.rawValue) root path '\(resolvedPath)': \(error.localizedDescription)",
                severity: .error
            )
        )
    }

    func presentCommandPalette(initialQuery: String, keyBindings: OpenMUXKeyBindingRegistry) {
        let previousResponder = view.window?.firstResponder
        let paletteView: CommandPaletteView
        if let existing = commandPaletteView {
            paletteView = existing
        } else {
            paletteView = CommandPaletteView()
            paletteView.setAccessibilityIdentifier(A11yID.commandPalette)
            commandPaletteView = paletteView
            shellOverlayHostView.present(commandPaletteView: paletteView)
        }
        paletteView.apply(theme: currentTheme)

        let configOpenContext = resolvedConfigOpenContext()
        paletteView.iconProvider = { id in
            id == "cli:omux.config.open" ? configOpenContext?.icon : nil
        }

        paletteView.resultProvider = { [weak self] query in
            guard let self else { return [] }
            let parsed = CommandPaletteParsedQuery(rawText: query)
            switch parsed.mode {
            case .workspace:
                return CommandPaletteSearch.workspaceResults(
                    query: parsed.matchingText,
                    workspaces: controller.commandPaletteWorkspaces()
                )
            case .command:
                let commands = CommandPaletteCommandCatalog.commands(
                    controller: controller,
                    keyBindings: keyBindings,
                    subtitleOverrides: configOpenContext.map { ["cli:omux.config.open": $0.subtitle] } ?? [:]
                )
                return CommandPaletteSearch.commandResults(
                    query: parsed.matchingText,
                    commands: commands
                )
            case .agentSession:
                if vaultConfiguration.enabled && vaultStore != nil {
                    ensureVaultPaletteSessionsLoaded(paletteView: paletteView)
                    return vaultPaletteResults(query: parsed.matchingText)
                }
                return []
            }
        }

        var themeBeforeSubPalette: WorkspaceShellTheme? = nil

        paletteView.invokeResult = { [weak self] result in
            guard let self else { return .failed("Window is unavailable") }
            if result.invocationTarget == .action(.sidebarToggle) {
                toggleSidebarVisibility()
                return .invoked
            }
            if result.invocationTarget == .action(.rightSidebarToggle) {
                toggleVaultSidebar()
                return .invoked
            }
            if result.invocationTarget == .action(.agentSessionsToggle) {
                toggleAgentSessionsPanel()
                return .invoked
            }
            if result.invocationTarget == .action(.paneFind) {
                commandPaletteView?.dismissAndRestoreFocus()
                presentPaneFind()
                return .invoked
            }
            if result.invocationTarget == .action(.paneTabClose) {
                guard controller.canClosePaneTab(), let paneID = currentWorkspace?.focusedPane?.id else {
                    return .failed("Pane tab could not be closed")
                }
                onClosePaneTab(paneID)
                return .invoked
            }
            if result.invocationTarget == .themeSwitch {
                themeBeforeSubPalette = currentTheme
                paletteView.enterThemeSubPalette(originalTheme: currentTheme)
                return .inert
            }
            if result.invocationTarget == .restoreWorkspacePalette {
                presentRestoreWorkspaceSubPalette(in: paletteView, controller: controller)
                return .inert
            }
            if result.invocationTarget == .clearRecentlyClosedWorkspaces {
                controller.clearRecentlyClosedWorkspaces()
                shellOverlayHostView.dismissAllWorkspaceRestoreBanners()
                return .invoked
            }
            if case .vaultSession(let sessionID) = result.invocationTarget {
                resumeVaultSession(sessionID)
                return .invoked
            }
            if result.invocationTarget == .configOpen {
                NSWorkspace.shared.open(OmuxConfigPaths.configFileURL)
                return .invoked
            }
            return controller.invokeCommandPaletteResult(result)
        }

        paletteView.subPalettePreviewHandler = { [weak self] identifier in
            guard let self else { return }
            if let theme = WorkspaceShellTheme.named(identifier) {
                updateTheme(theme)
            }
        }

        paletteView.subPaletteCommitHandler = { [weak self] identifier in
            guard let self else { return }
            if identifier.hasPrefix("recently-closed:") {
                let workspaceIDRaw = String(identifier.dropFirst("recently-closed:".count))
                let workspaceID = WorkspaceID(rawValue: workspaceIDRaw)
                self.restoreClosedWorkspaceFromPalette(workspaceID: workspaceID, controller: self.controller)
                return
            }
            themeBeforeSubPalette = nil
            self.themeCommitHandler?(identifier)
        }

        paletteView.subPaletteRevertHandler = { [weak self] in
            guard let self else { return }
            if let saved = themeBeforeSubPalette {
                updateTheme(saved)
                themeBeforeSubPalette = nil
            }
        }

        paletteView.dismissHandler = { [weak self, weak paletteView] in
            if self?.commandPaletteView === paletteView {
                self?.commandPaletteView = nil
            }
            self?.vaultPaletteSessionsLoaded = false
            if let paletteView {
                self?.shellOverlayHostView.dismiss(commandPaletteView: paletteView)
            }
        }
        paletteView.present(initialQuery: initialQuery, restoring: previousResponder)
    }

    func presentAgentSessionsPalette(keyBindings: OpenMUXKeyBindingRegistry) {
        presentCommandPalette(initialQuery: "@", keyBindings: keyBindings)
    }

    override func cancelOperation(_ sender: Any?) {
        guard commandPaletteView == nil,
              let paneID = currentWorkspace?.focusedFloatingPaneModal?.focusedPane?.id
        else {
            super.cancelOperation(sender)
            return
        }

        onClosePaneTab(paneID)
    }

    func presentPaneFind(initialQuery: String = "") {
        guard let pane = currentWorkspace?.focusedPane, isSearchablePane(pane) else { return }
        if let existing = paneFindBarView {
            if initialQuery.isEmpty {
                existing.present(existingQuery: existing.currentQuery)
            } else {
                existing.present(existingQuery: initialQuery)
                applySearch(to: existing, query: initialQuery)
            }
            return
        }

        let findBar = PaneFindBarView()
        paneFindBarView = findBar
        canvasView.addSubview(findBar)
        NSLayoutConstraint.activate([
            findBar.trailingAnchor.constraint(equalTo: canvasView.trailingAnchor, constant: -8),
            findBar.bottomAnchor.constraint(equalTo: canvasView.bottomAnchor, constant: -8),
            findBar.widthAnchor.constraint(equalToConstant: 460),
        ])

        findBar.onDismiss = { [weak self, weak findBar] in
            self?.stopFindSearch()
            findBar?.removeFromSuperview()
            if self?.paneFindBarView === findBar {
                self?.paneFindBarView = nil
            }
        }

        findBar.onSearch = { [weak self, weak findBar] query in
            guard let self, let findBar else { return }
            applySearch(to: findBar, query: query)
        }

        findBar.onNavigate = { [weak self, weak findBar] forward in
            guard let self, let findBar else { return }
            navigateSearch(in: findBar, forward: forward)
        }

        // Observe Ghostty search callbacks to update match count label
        let token = controller.terminalBridge.addTerminalActionObserver { [weak findBar] event in
            guard case .searchMatchesUpdated(let total, let selected) = event.action else { return }
            DispatchQueue.main.async {
                findBar?.updateMatchCount(total: total, selected: selected)
            }
        }
        findSearchObserverToken = token

        findBar.present(existingQuery: initialQuery)
        if !initialQuery.isEmpty {
            applySearch(to: findBar, query: initialQuery)
        }
    }

    func dismissPaneFind() {
        paneFindBarView?.onDismiss?()
    }

    private func applySearch(to findBar: PaneFindBarView, query: String) {
        let bridge = controller.terminalBridge
        guard let pane = currentWorkspace?.focusedPane, isSearchablePane(pane) else { return }
        try? bridge.search(paneID: pane.id, needle: query)
        let snapshot = bridge.terminalTextSnapshot(for: pane.id)
        if snapshot.isAvailable {
            let total = PaneFindSearch.matchCount(query: query, in: snapshot.text)
            findBar.updateMatchCount(total: total, selected: total > 0 ? 0 : -1)
        }
    }

    private func navigateSearch(in findBar: PaneFindBarView, forward: Bool) {
        let bridge = controller.terminalBridge
        guard let pane = currentWorkspace?.focusedPane, isSearchablePane(pane) else { return }
        try? bridge.navigateSearch(paneID: pane.id, forward: forward)
    }

    private func reapplyActiveFindSearch(previousPaneID: PaneID?) {
        guard let findBar = paneFindBarView else { return }
        let query = findBar.currentQuery
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let focusedPane = currentWorkspace?.focusedPane
        if let previousPaneID,
           previousPaneID != focusedPane?.id,
           let previousPane = pane(withID: previousPaneID),
           isSearchablePane(previousPane)
        {
            try? controller.terminalBridge.endSearch(paneID: previousPaneID)
        }
        guard let focusedPane, isSearchablePane(focusedPane) else { return }
        applySearch(to: findBar, query: query)
    }

    private func stopFindSearch() {
        if let token = findSearchObserverToken {
            controller.terminalBridge.removeTerminalActionObserver(token: token)
            findSearchObserverToken = nil
        }
        // End search on all active pane surfaces
        let bridge = controller.terminalBridge
        let allPanes = controller.allWorkspaces().flatMap(\.panes)
        for pane in allPanes {
            try? bridge.endSearch(paneID: pane.id)
        }
    }

    private func isSearchablePane(_ pane: Pane) -> Bool {
        pane.isTerminal
    }

    private func pane(withID paneID: PaneID) -> Pane? {
        controller.allWorkspaces()
            .flatMap(\.panes)
            .first { $0.id == paneID }
    }

    private func ensureVaultPaletteSessionsLoaded(paletteView: CommandPaletteView) {
        guard !vaultPaletteSessionsLoaded else { return }
        vaultPaletteSessionsLoaded = true
        vaultPaletteSessions = []
        vaultPaletteEntries = []
        loadVaultPaletteSessions(paletteView: paletteView)
    }

    private func presentRestoreWorkspaceSubPalette(
        in paletteView: CommandPaletteView,
        controller: WorkspaceController
    ) {
        paletteView.enterRestoreWorkspaceSubPalette { [weak controller] query in
            guard let controller else { return [] }
            let entries = controller.commandPaletteRecentlyClosedWorkspaces()
            return CommandPaletteSearch.recentlyClosedResults(query: query, entries: entries)
        }
    }

    private func restoreClosedWorkspaceFromPalette(
        workspaceID: WorkspaceID,
        controller: WorkspaceController
    ) {
        let entries = controller.commandPaletteRecentlyClosedWorkspaces()
        guard let entry = entries.first(where: { $0.id == workspaceID }) else {
            try? controller.notify(
                NotificationRequest(
                    title: "Restore failed",
                    body: "Workspace no longer in recently closed list",
                    severity: .error
                )
            )
            return
        }
        do {
            _ = try controller.reopenClosedWorkspace(entry)
            controller.removeRecentlyClosedWorkspace(byID: entry.id)
        } catch {
            try? controller.notify(
                NotificationRequest(
                    title: "Restore failed",
                    body: error.localizedDescription,
                    severity: .error
                )
            )
        }
    }

    private func loadVaultPaletteSessions(paletteView: CommandPaletteView) {
        guard let vaultStore else {
            return
        }

        let generation = UUID()
        vaultPaletteLoadGeneration = generation
        Task { [weak self, weak paletteView] in
            var sessions: [VaultSessionSummary] = []
            var offset = 0
            var totalCount = Int.max

            do {
                repeat {
                    let response = try await vaultStore.search(VaultSearchRequest(offset: offset, limit: 500))
                    sessions += response.sessions
                    offset += response.sessions.count
                    totalCount = response.totalCount

                    guard let self,
                          let paletteView,
                          self.vaultPaletteLoadGeneration == generation
                    else {
                        return
                    }
                    self.vaultPaletteSessions = sessions
                    self.vaultPaletteEntries = sessions.enumerated().map { index, session in
                        VaultPaletteEntry(session: session, searchTexts: self.vaultPaletteSearchTexts(for: session), index: index)
                    }
                    paletteView.refreshPresentedResults()

                    if response.sessions.isEmpty {
                        break
                    }
                } while offset < totalCount
            } catch {
                fputs("Agent Sessions palette search failed: \(error)\n", stderr)
                guard let self, self.vaultPaletteLoadGeneration == generation else { return }
                self.vaultPaletteSessionsLoaded = false
            }
        }
    }

    private func vaultPaletteResults(query: String) -> [CommandPaletteResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let ranked: [VaultPaletteEntry]
        if normalizedQuery.isEmpty {
            ranked = Array(vaultPaletteEntries.prefix(Self.vaultPaletteResultLimit))
        } else {
            ranked = vaultPaletteEntries.compactMap { entry -> (entry: VaultPaletteEntry, score: Int)? in
                let score = entry.searchTexts
                    .compactMap { Self.vaultPaletteMatchScore(query: normalizedQuery, candidate: $0) }
                    .min()
                guard let score else { return nil }
                return (entry, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.entry.index < rhs.entry.index
            }
            .prefix(Self.vaultPaletteResultLimit)
            .map(\.entry)
        }

        return ranked.map { entry in
            let session = entry.session
            let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? session.id
                : session.title
            let subtitleParts = [
                session.agent.rawValue,
                session.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent },
            ].compactMap { $0 }.filter { $0.isEmpty == false }

            return CommandPaletteResult(
                id: session.id,
                title: title,
                subtitle: subtitleParts.joined(separator: " · "),
                category: .action,
                matchText: [
                    title,
                    session.id,
                    session.agent.rawValue,
                    session.workingDirectory,
                    session.model,
                    session.gitBranch,
                ].compactMap { $0 }.joined(separator: " "),
                invocationTarget: .vaultSession(session.id)
            )
        }
    }

    private static let vaultPaletteResultLimit = 80

    private struct VaultPaletteEntry {
        let session: VaultSessionSummary
        let searchTexts: [String]
        let index: Int
    }

    private func vaultPaletteSearchTexts(for session: VaultSessionSummary) -> [String] {
        [
            session.title,
            session.id,
            session.agent.rawValue,
            session.workingDirectory,
            session.model,
            session.gitBranch,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
        .filter { $0.isEmpty == false }
    }

    private static func vaultPaletteMatchScore(query: String, candidate: String) -> Int? {
        guard query.isEmpty == false else {
            return 0
        }
        if candidate == query { return 0 }
        if candidate.hasPrefix(query) { return 10 }
        if candidate.contains(query) { return 20 }
        let parts = query.split(separator: " ")
        if parts.allSatisfy({ candidate.contains($0) }) { return 30 }
        return fuzzySubsequenceScore(query: query, candidate: candidate).map { 40 + $0 }
    }

    private static func fuzzySubsequenceScore(query: String, candidate: String) -> Int? {
        var score = 0
        var searchStart = candidate.startIndex
        for character in query {
            guard let match = candidate[searchStart...].firstIndex(of: character) else {
                return nil
            }
            score += candidate.distance(from: searchStart, to: match)
            searchStart = candidate.index(after: match)
        }
        return score
    }

    private struct ConfigOpenContext {
        let subtitle: String
        let icon: NSImage
    }

    private func resolvedConfigOpenContext() -> ConfigOpenContext? {
        guard let appURL = resolveDefaultAppForTOML() else { return nil }
        let appBundle = Bundle(url: appURL)
        let appName = appBundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? appBundle?.infoDictionary?["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        return ConfigOpenContext(subtitle: "Opens in \(appName)", icon: icon)
    }

    private func resolveDefaultAppForTOML() -> URL? {
        let configURL = OmuxConfigPaths.configFileURL
        if FileManager.default.fileExists(atPath: configURL.path) {
            return NSWorkspace.shared.urlForApplication(toOpen: configURL)
        }
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("omux-probe.toml")
        guard (try? "".write(to: probe, atomically: true, encoding: .utf8)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: probe) }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    private func presentRenamePanePrompt(paneID: PaneID, currentTitle: String) {
        let nameField = NSTextField(string: currentTitle)
        nameField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)

        presentConfirmation(
            title: "Rename Tab",
            message: "Set a custom tab name. Leave empty to clear the custom name.",
            actionTitle: "Save",
            alertStyle: .informational,
            accessoryView: nameField
        ) { [weak self] in
            guard let self else { return }
            let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                _ = try? controller.clearPaneAlias(paneID)
            } else {
                _ = try? controller.setPaneAlias(paneID, to: trimmed)
            }
        }
    }

    private func makeWorkspaceContextMenu(for workspace: Workspace, onBeginRename: (() -> Void)?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename…", action: nil, keyEquivalent: "").onSelect { [weak self] in
            if let onBeginRename {
                onBeginRename()
            } else {
                self?.presentRenameWorkspacePrompt(workspaceID: workspace.id)
            }
        }
        menu.addItem(withTitle: "Set Root Path…", action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.presentWorkspaceRootPrompt(workspaceID: workspace.id)
        }
        let resetRootTitle = workspace.rootPathMode == .manual
            ? "Use Automatic Root"
            : "Recompute Automatic Root"
        menu.addItem(withTitle: resetRootTitle, action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.resetWorkspaceRootToAutomatic(workspaceID: workspace.id)
        }
        let expansionTitle = collapsedWorkspaceIDs.contains(workspace.id)
            ? "Expand Workspace Panes"
            : "Collapse Workspace Panes"
        menu.addItem(withTitle: expansionTitle, action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.toggleWorkspaceExpansion(workspace.id)
        }
        if workspace.hasCustomName {
            menu.addItem(withTitle: "Remove Custom Name", action: nil, keyEquivalent: "").onSelect { [weak self] in
                _ = self?.controller.removeCustomWorkspaceName(workspace.id)
            }
        }
        menu.addItem(.separator())

        let closeItem = menu.addItem(withTitle: "Close", action: nil, keyEquivalent: "")
        closeItem.isEnabled = controller.allWorkspaces().count > 1
        closeItem.onSelect { [weak self] in
            _ = try? self?.controller.closeWorkspace(workspace.id)
        }

        let index = controller.allWorkspaces().firstIndex(where: { $0.id == workspace.id }) ?? 0
        let totalCount = controller.allWorkspaces().count

        let closeOthersItem = menu.addItem(withTitle: "Close Others", action: nil, keyEquivalent: "")
        closeOthersItem.isEnabled = totalCount > 1
        closeOthersItem.onSelect { [weak self] in
            _ = try? self?.controller.closeOtherWorkspaces(keeping: workspace.id)
        }

        let closeAboveItem = menu.addItem(withTitle: "Close Above", action: nil, keyEquivalent: "")
        closeAboveItem.isEnabled = index > 0
        closeAboveItem.onSelect { [weak self] in
            _ = try? self?.controller.closeWorkspacesAbove(workspace.id)
        }

        let closeBelowItem = menu.addItem(withTitle: "Close Below", action: nil, keyEquivalent: "")
        closeBelowItem.isEnabled = index < totalCount - 1
        closeBelowItem.onSelect { [weak self] in
            _ = try? self?.controller.closeWorkspacesBelow(workspace.id)
        }
        return menu
    }

    private func makePaneTabContextMenu(
        pane: Pane,
        paneStack: PaneStack,
        canCloseSinglePaneStack: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename…", action: nil, keyEquivalent: "").onSelect { [weak self] in
            self?.presentRenamePanePrompt(paneID: pane.id, currentTitle: pane.displayTitle)
        }

        let popOutItem = menu.addItem(withTitle: "Pop Out to Modal", action: nil, keyEquivalent: "")
        popOutItem.isEnabled = canPopOutPaneTab(paneID: pane.id, sourceStackID: paneStack.id, allowSinglePane: true)
        popOutItem.onSelect { [weak self] in
            _ = self?.controller.movePaneTabToFloatingModal(
                paneID: pane.id,
                sourceStackID: paneStack.id
            )
        }

        let closeItem = menu.addItem(withTitle: "Close", action: nil, keyEquivalent: "")
        closeItem.isEnabled = paneStack.panes.count > 1 || canCloseSinglePaneStack
        closeItem.onSelect { [weak self] in
            self?.onClosePaneTab(pane.id)
        }

        let targetIndex = paneStack.panes.firstIndex(where: { $0.id == pane.id }) ?? 0

        let closeOthersItem = menu.addItem(withTitle: "Close Others", action: nil, keyEquivalent: "")
        closeOthersItem.isEnabled = paneStack.panes.count > 1
        closeOthersItem.onSelect { [weak self] in
            _ = try? self?.controller.closeOtherPaneTabs(paneID: pane.id)
        }

        let closeAboveItem = menu.addItem(withTitle: "Close Above", action: nil, keyEquivalent: "")
        closeAboveItem.isEnabled = targetIndex > 0
        closeAboveItem.onSelect { [weak self] in
            _ = try? self?.controller.closePaneTabsAbove(paneID: pane.id)
        }

        let closeBelowItem = menu.addItem(withTitle: "Close Below", action: nil, keyEquivalent: "")
        closeBelowItem.isEnabled = targetIndex < paneStack.panes.count - 1
        closeBelowItem.onSelect { [weak self] in
            _ = try? self?.controller.closePaneTabsBelow(paneID: pane.id)
        }
        return menu
    }

    private struct WorkspaceReconciliationMetrics {
        var reusedHostViews: Int = 0
        var rebuiltHostViews: Int = 0
    }

    private func logReconciliationMetricsIfNeeded(_ metrics: WorkspaceReconciliationMetrics) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["OMUX_DEBUG_RECONCILE"] == "1" else {
            return
        }
        guard metrics.reusedHostViews > 0 || metrics.rebuiltHostViews > 0 else {
            return
        }
        print("omux.appshell.reconcile reused=\(metrics.reusedHostViews) rebuilt=\(metrics.rebuiltHostViews)")
        #endif
    }

    @MainActor
    private func registerRenamePaneTabUndo(
        paneID: PaneID,
        oldAlias: String?,
        newName: String
    ) {
        guard let undoManager = view.window?.undoManager else {
            return
        }

        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                if let oldAlias {
                    _ = try? target.controller.setPaneAlias(paneID, to: oldAlias)
                } else {
                    _ = try? target.controller.clearPaneAlias(paneID)
                }
                target.registerRenamePaneTabRedo(paneID: paneID, newName: newName)
            }
        }
        undoManager.setActionName("Rename Tab")
    }

    @MainActor
    private func registerRenamePaneTabRedo(
        paneID: PaneID,
        newName: String
    ) {
        guard let undoManager = view.window?.undoManager else {
            return
        }

        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                _ = try? target.controller.setPaneAlias(paneID, to: newName)
                target.view.window?.undoManager?.setActionName("Rename Tab")
            }
        }
    }

    @MainActor
    private func registerClearPaneTabAliasUndo(
        paneID: PaneID,
        oldAlias: String?
    ) {
        guard let undoManager = view.window?.undoManager else {
            return
        }

        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                if let oldAlias {
                    _ = try? target.controller.setPaneAlias(paneID, to: oldAlias)
                }
            }
        }
        undoManager.setActionName("Clear Tab Name")
    }

    private func makeRenamePaneTabHandler() -> (PaneID, String) -> Void {
        { [weak self] paneID, newName in
            guard let self else { return }
            let oldAlias = controller.pane(paneID)?.userAlias
            guard let _ = try? controller.setPaneAlias(paneID, to: newName) else { return }
            self.registerRenamePaneTabUndo(paneID: paneID, oldAlias: oldAlias, newName: newName)
        }
    }

    private func makeClearPaneTabAliasHandler() -> (PaneID) -> Void {
        { [weak self] paneID in
            guard let self else { return }
            let oldAlias = controller.pane(paneID)?.userAlias
            guard let _ = try? controller.clearPaneAlias(paneID) else { return }
            self.registerClearPaneTabAliasUndo(paneID: paneID, oldAlias: oldAlias)
        }
    }

    private func reconcileLayoutView(
        existingView: NSView,
        node: TabLayoutNode,
        focusedPaneID: PaneID,
        windowIsKey: Bool,
        inactiveOpacity: Double,
        canCloseSinglePaneStack: Bool,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?
    ) -> (success: Bool, focusedPaneView: NSView?, reusedPaneStackViews: Int)? {
        switch node {
        case .paneStack(let paneStack):
            guard let stackView = existingView as? PaneStackView else {
                return nil
            }
            stackView.update(
                paneStack: paneStack,
                focusedPaneID: focusedPaneID,
                windowIsKey: windowIsKey,
                inactiveOpacity: inactiveOpacity,
                bridge: controller.terminalBridge,
                theme: currentTheme,
                iconResolver: iconResolver,
                iconConfiguration: currentIcons,
                terminalTextProvider: terminalTextProvider,
                onSelectPaneTab: { [weak self] paneID in
                    _ = self?.controller.focusPaneTab(paneID: paneID)
                },
                onCreatePaneTab: { [weak self] in
                    _ = try self?.controller.createPaneTab(in: paneStack.id)
                },
                canCloseSinglePaneStack: canCloseSinglePaneStack,
                onClosePane: { [weak self] paneID in
                    self?.onClosePaneTab(paneID)
                },
                contextMenuProvider: { [weak self] pane in
                    guard let self else { return NSMenu() }
                    return makePaneTabContextMenu(
                        pane: pane,
                        paneStack: paneStack,
                        canCloseSinglePaneStack: canCloseSinglePaneStack
                    )
                },
                onFocus: { [weak self] paneID in
                    _ = self?.controller.focus(paneID: paneID)
                },
                canStartPaneTabDrag: { [weak self] paneID in
                    self?.canStartPaneTabDrag(paneID: paneID, sourceStackID: paneStack.id) ?? false
                },
                onPaneTabDragStarted: { [weak self] button, paneID, stackID, _ in
                    self?.beginPaneTabDrag(button: button, paneID: paneID, sourceStackID: stackID)
                },
                onPaneTabDragMoved: { [weak self] _, _, event in
                    self?.updatePaneTabDrag(with: event)
                },
                onPaneTabDragEnded: { [weak self] _, _, event in
                    self?.endPaneTabDrag(with: event)
                },
                onPaneTabDragCancelled: { [weak self] in
                    self?.cancelPaneTabDrag()
                },
                onTextActivation: { [weak self] request in
                    self?.controller.handleTerminalTextActivation(request) ?? false
                },
                onTextActivationHover: { [weak self] request in
                    self?.controller.canHandleTerminalTextActivation(request) ?? false
                },
                onExtensionPaneAction: { [weak self] request in
                    self?.onExtensionPaneAction(request)
                },
                onRenamePaneTab: makeRenamePaneTabHandler(),
                onClearPaneTabAlias: makeClearPaneTabAliasHandler()
            )
            return (true, paneStack.focusedPaneID == focusedPaneID ? stackView.focusedPaneView : nil, 1)

        case .split(let axis, let proportions, let children):
            guard let splitView = existingView as? SplitLayoutView,
                  splitView.canReconcile(axis: axis, childCount: children.count)
            else {
                return nil
            }

            let childViews = splitView.childLayoutViews
            guard childViews.count == children.count else {
                return nil
            }

            var focusedPaneView: NSView?
            var reusedPaneStackViews = 0
            var childPaneIDs: [PaneID] = []

            for (index, child) in children.enumerated() {
                guard let childResult = reconcileLayoutView(
                    existingView: childViews[index],
                    node: child,
                    focusedPaneID: focusedPaneID,
                    windowIsKey: windowIsKey,
                    inactiveOpacity: inactiveOpacity,
                    canCloseSinglePaneStack: canCloseSinglePaneStack,
                    terminalTextProvider: terminalTextProvider
                ) else {
                    return nil
                }
                if focusedPaneView == nil {
                    focusedPaneView = childResult.focusedPaneView
                }
                reusedPaneStackViews += childResult.reusedPaneStackViews
                if let representativePaneID = child.representativePaneID {
                    childPaneIDs.append(representativePaneID)
                }
            }

            splitView.updateLayout(
                proportions: proportions,
                childPaneIDs: childPaneIDs
            )
            return (true, focusedPaneView, reusedPaneStackViews)
        }
    }

    private func makeLayoutView(
        for node: TabLayoutNode,
        focusedPaneID: PaneID,
        windowIsKey: Bool,
        inactiveOpacity: Double,
        canCloseSinglePaneStack: Bool,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?
    ) -> (view: NSView, focusedPaneView: NSView?, representativePaneID: PaneID?) {
        switch node {
        case .paneStack(let paneStack):
            let stackView = PaneStackView(
                paneStack: paneStack,
                focusedPaneID: focusedPaneID,
                windowIsKey: windowIsKey,
                inactiveOpacity: inactiveOpacity,
                bridge: controller.terminalBridge,
                theme: currentTheme,
                iconResolver: iconResolver,
                iconConfiguration: currentIcons,
                terminalTextProvider: terminalTextProvider,
                onSelectPaneTab: { [weak self] paneID in
                    _ = self?.controller.focusPaneTab(paneID: paneID)
                },
                onCreatePaneTab: { [weak self] in
                    _ = try self?.controller.createPaneTab(in: paneStack.id)
                },
                canCloseSinglePaneStack: canCloseSinglePaneStack,
                onClosePane: { [weak self] paneID in
                    self?.onClosePaneTab(paneID)
                },
                contextMenuProvider: { [weak self] pane in
                    guard let self else { return NSMenu() }
                    return makePaneTabContextMenu(
                        pane: pane,
                        paneStack: paneStack,
                        canCloseSinglePaneStack: canCloseSinglePaneStack
                    )
                },
                onFocus: { [weak self] paneID in
                    _ = self?.controller.focus(paneID: paneID)
                },
                canStartPaneTabDrag: { [weak self] paneID in
                    self?.canStartPaneTabDrag(paneID: paneID, sourceStackID: paneStack.id) ?? false
                },
                onPaneTabDragStarted: { [weak self] button, paneID, stackID, _ in
                    self?.beginPaneTabDrag(button: button, paneID: paneID, sourceStackID: stackID)
                },
                onPaneTabDragMoved: { [weak self] _, _, event in
                    self?.updatePaneTabDrag(with: event)
                },
                onPaneTabDragEnded: { [weak self] _, _, event in
                    self?.endPaneTabDrag(with: event)
                },
                onPaneTabDragCancelled: { [weak self] in
                    self?.cancelPaneTabDrag()
                },
                onTextActivation: { [weak self] request in
                    self?.controller.handleTerminalTextActivation(request) ?? false
                },
                onTextActivationHover: { [weak self] request in
                    self?.controller.canHandleTerminalTextActivation(request) ?? false
                },
                onExtensionPaneAction: { [weak self] request in
                    self?.onExtensionPaneAction(request)
                },
                onRenamePaneTab: makeRenamePaneTabHandler(),
                onClearPaneTabAlias: makeClearPaneTabAliasHandler()
            )
            return (
                stackView,
                paneStack.focusedPaneID == focusedPaneID ? stackView.focusedPaneView : nil,
                paneStack.panes.first?.id
            )

        case .split(let axis, let proportions, let children):
            var focusedPaneView: NSView?
            var childViews: [NSView] = []
            var childPaneIDs: [PaneID] = []

            for child in children {
                let childLayout = makeLayoutView(
                    for: child,
                    focusedPaneID: focusedPaneID,
                    windowIsKey: windowIsKey,
                    inactiveOpacity: inactiveOpacity,
                    canCloseSinglePaneStack: canCloseSinglePaneStack,
                    terminalTextProvider: terminalTextProvider
                )
                if focusedPaneView == nil {
                    focusedPaneView = childLayout.focusedPaneView
                }
                childViews.append(childLayout.view)
                if let representativePaneID = childLayout.representativePaneID {
                    childPaneIDs.append(representativePaneID)
                }
            }

            let splitView = SplitLayoutView(
                axis: axis,
                proportions: proportions,
                childPaneIDs: childPaneIDs,
                onResize: { [weak self] childPaneIDs, proportions in
                    _ = self?.controller.updateSplitProportions(proportions, forChildPaneIDs: childPaneIDs)
                }
            )
            childViews.forEach { childView in
                childView.translatesAutoresizingMaskIntoConstraints = true
                splitView.addSubview(childView)
            }

            return (splitView, focusedPaneView, children.first?.representativePaneID)
        }
    }

    private func renderFloatingPaneModals(
        workspace: Workspace,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?
    ) -> NSView? {
        let orderedModals = workspace.floatingPaneModals.sorted { lhs, rhs in
            if workspace.focusedFloatingPaneModalID == lhs.id { return false }
            if workspace.focusedFloatingPaneModalID == rhs.id { return true }
            return lhs.id.rawValue < rhs.id.rawValue
        }

        var focusedPaneView: NSView?
        let modalViews = orderedModals.map { modal -> FloatingPaneModalView in
            let layout = PaneStackView(
                paneStack: modal.paneStack,
                focusedPaneID: modal.paneStack.focusedPaneID,
                windowIsKey: windowIsKey,
                inactiveOpacity: currentPanes.inactiveOpacity,
                bridge: controller.terminalBridge,
                theme: currentTheme,
                iconResolver: iconResolver,
                iconConfiguration: currentIcons,
                terminalTextProvider: terminalTextProvider,
                onSelectPaneTab: { [weak self] paneID in
                    _ = self?.controller.focusPaneTab(paneID: paneID)
                },
                onCreatePaneTab: { [weak self] in
                    _ = try self?.controller.createPaneTab(in: modal.paneStack.id)
                },
                canCloseSinglePaneStack: true,
                onClosePane: { [weak self] paneID in
                    self?.onClosePaneTab(paneID)
                },
                contextMenuProvider: { [weak self] pane in
                    guard let self else { return NSMenu() }
                    return makePaneTabContextMenu(
                        pane: pane,
                        paneStack: modal.paneStack,
                        canCloseSinglePaneStack: true
                    )
                },
                onFocus: { [weak self] paneID in
                    _ = self?.controller.focus(paneID: paneID)
                },
                canStartPaneTabDrag: { _ in false },
                onTextActivation: { [weak self] request in
                    self?.controller.handleTerminalTextActivation(request) ?? false
                },
                onTextActivationHover: { [weak self] request in
                    self?.controller.canHandleTerminalTextActivation(request) ?? false
                },
                onExtensionPaneAction: { [weak self] request in
                    self?.onExtensionPaneAction(request)
                },
                showsHeader: false
            )
            if workspace.focusedFloatingPaneModalID == modal.id {
                focusedPaneView = layout.focusedPaneView
            }
            return FloatingPaneModalView(
                modalID: modal.id,
                paneID: modal.paneStack.focusedPaneID,
                sourceStackID: modal.paneStack.id,
                title: modal.paneStack.focusedPane?.title ?? "Pane",
                contentView: layout,
                frameModel: modal.frame,
                theme: currentTheme,
                onFocus: { [weak self] paneID in
                    _ = self?.controller.focus(paneID: paneID)
                },
                onClose: { [weak self] paneID in
                    self?.onClosePaneTab(paneID)
                },
                onDragChanged: { [weak self] paneID, sourceStackID, _, frame, allowsDocking in
                    self?.updateFloatingModalDragPreview(
                        paneID: paneID,
                        sourceStackID: sourceStackID,
                        frame: frame,
                        allowsDocking: allowsDocking
                    )
                },
                onDragEnded: { [weak self] paneID, sourceStackID, modalID, frame, allowsDocking in
                    self?.finishFloatingModalDrag(
                        paneID: paneID,
                        sourceStackID: sourceStackID,
                        modalID: modalID,
                        frame: frame,
                        allowsDocking: allowsDocking
                    )
                }
            )
        }

        floatingModalOverlayView.render(modalViews: modalViews)
        return focusedPaneView
    }

    private enum FloatingModalDropIntent {
        case merge(PaneStackID)
        case split(PaneStackID, PaneSplitDropDirection)
        case splitAtRoot(PaneSplitDropDirection)
    }

    private func updateFloatingModalDragPreview(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        frame: NSRect,
        allowsDocking: Bool
    ) {
        clearPaneTabSplitPreview()
        guard let intent = floatingModalDropIntent(
            paneID: paneID,
            sourceStackID: sourceStackID,
            frame: frame,
            allowsDocking: allowsDocking
        ) else {
            return
        }

        switch intent {
        case .merge(let targetStackID):
            paneStackView(with: targetStackID)?.setMergePreview(theme: currentTheme)
        case .split(let targetStackID, let direction):
            paneStackView(with: targetStackID)?.setSplitPreview(direction, theme: currentTheme)
        case .splitAtRoot(let direction):
            canvasView.setRootSplitPreview(direction, theme: currentTheme)
        }
    }

    private func finishFloatingModalDrag(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        modalID: FloatingPaneModalID,
        frame: NSRect,
        allowsDocking: Bool
    ) {
        defer { clearPaneTabSplitPreview() }
        if let intent = floatingModalDropIntent(
            paneID: paneID,
            sourceStackID: sourceStackID,
            frame: frame,
            allowsDocking: allowsDocking
        ) {
            switch intent {
            case .merge(let targetStackID):
                _ = try? controller.movePaneTabToStack(
                    paneID: paneID,
                    sourceStackID: sourceStackID,
                    targetStackID: targetStackID
                )
            case .split(let targetStackID, let direction):
                _ = try? controller.movePaneTabToSplit(
                    paneID: paneID,
                    sourceStackID: sourceStackID,
                    targetStackID: targetStackID,
                    direction: direction
                )
            case .splitAtRoot(let direction):
                _ = controller.dockFloatingPaneModalToRootSplit(modalID: modalID, direction: direction)
            }
            return
        }

        _ = controller.updateFloatingPaneModalFrame(
            modalID: modalID,
            frame: FloatingPaneModalFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        )
    }

    private func floatingModalDropIntent(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        frame: NSRect,
        allowsDocking: Bool
    ) -> FloatingModalDropIntent? {
        guard allowsDocking else {
            return nil
        }

        let headerPoint = NSPoint(x: frame.midX, y: frame.minY + ShellLayoutMetrics.paneHeaderHeight / 2)
        let headerPointInWindow = floatingModalOverlayView.convert(headerPoint, to: nil)
        if let targetView = paneStackView(in: canvasView, atWindowLocation: headerPointInWindow),
           let targetStackID = targetView.paneStackID,
           targetStackID != sourceStackID
        {
            if targetView.isWindowPointInHeader(headerPointInWindow) {
                return .merge(targetStackID)
            }

            let localPoint = targetView.convert(headerPointInWindow, from: nil)
            if let direction = PaneSplitDropIntentResolver.direction(for: localPoint, in: targetView.bounds) {
                return .split(targetStackID, direction)
            }
        }

        return floatingModalRootSplitDirection(for: frame).map(FloatingModalDropIntent.splitAtRoot)
    }

    private func floatingModalRootSplitDirection(for frame: NSRect) -> PaneSplitDropDirection? {
        WorkspaceWindowFloatingModalDropResolver.rootSplitDirection(
            frame: frame,
            overlayBounds: floatingModalOverlayView.bounds,
            threshold: PaneSplitDropIntentResolver.outerEdgeThreshold
        )
    }

    // MARK: - Pane Tab Drag

    private enum PaneTabDropIntent {
        case split(PaneSplitDropDirection)
        case splitAtRoot(PaneSplitDropDirection)
        case merge
        case reorder(Int)
        case tearOut(FloatingPaneModalFrame)
    }

    private struct PaneTabDragState {
        let paneID: PaneID
        let sourceStackID: PaneStackID
        weak var sourceButton: NSView?
        var targetStackID: PaneStackID?
        var dropIntent: PaneTabDropIntent?
        var ghostView: NSView?
    }
    private var paneTabDragState: PaneTabDragState?
    private var deferredWorkspaceUpdateDuringPaneTabDrag: Workspace?

    private func canStartPaneTabDrag(paneID: PaneID, sourceStackID: PaneStackID) -> Bool {
        guard let workspace = currentWorkspace else {
            return false
        }
        if let tab = workspace.tabs.first(where: { $0.rootLayout.paneStack(id: sourceStackID) != nil }) {
            return PaneTabDragReadiness.canStart(
                paneID: paneID,
                sourceStackID: sourceStackID,
                in: tab,
                attachedSessionExists: controller.terminalBridge.attachedSession(for: paneID) != nil
            )
        }
        guard let pane = workspace.floatingPaneModals
            .first(where: { $0.paneStack.id == sourceStackID })?
            .paneStack.panes.first(where: { $0.id == paneID }),
              let extensionPane = pane.extensionPane
        else {
            return false
        }
        return extensionPane.status == .ready
    }

    private func beginPaneTabDrag(button: NSView, paneID: PaneID, sourceStackID: PaneStackID) {
        guard canStartPaneTabDrag(paneID: paneID, sourceStackID: sourceStackID) else {
            return
        }
        clearPaneTabSplitPreview()
        deferredWorkspaceUpdateDuringPaneTabDrag = nil
        let ghost = makePaneTabDragGhost(for: button)
        paneTabDragState = PaneTabDragState(
            paneID: paneID,
            sourceStackID: sourceStackID,
            sourceButton: button,
            targetStackID: nil,
            dropIntent: nil,
            ghostView: ghost
        )
    }

    private func updatePaneTabDrag(with event: NSEvent) {
        guard var dragState = paneTabDragState else { return }
        updatePaneTabDragGhost(dragState.ghostView, with: event)
        clearPaneTabSplitPreview()

        // Title bar zone (above the canvas) → full-width split above all panes.
        let canvasFrameInWindow = canvasView.convert(canvasView.bounds, to: nil)
        if event.locationInWindow.y > canvasFrameInWindow.maxY {
            canvasView.setRootSplitPreview(.up, theme: currentTheme)
            dragState.targetStackID = nil
            dragState.dropIntent = .splitAtRoot(.up)
            paneTabDragState = dragState
            return
        }

        // Resolve the pane under the cursor first — merge takes highest priority.
        if let targetView = paneStackView(atWindowLocation: event.locationInWindow),
           let targetStackID = targetView.paneStackID
        {
            if targetView.isWindowPointInHeader(event.locationInWindow) {
                targetView.setMergePreview(theme: currentTheme)
                dragState.targetStackID = targetStackID

                if targetStackID == dragState.sourceStackID {
                    let insertionIndex = targetView.paneTabInsertionIndex(forWindowPoint: event.locationInWindow) ?? 0
                    dragState.dropIntent = .reorder(insertionIndex)
                } else {
                    // Hovering over the tab strip of a different pane → merge into that stack.
                    dragState.dropIntent = .merge
                }

                paneTabDragState = dragState
                return
            }

            // Canvas outer-edge zone — but only when NOT in another pane's header.
            let canvasPoint = canvasView.convert(event.locationInWindow, from: nil)
            if let rootDirection = PaneSplitDropIntentResolver.outerEdgeDirection(for: canvasPoint, in: canvasView.bounds) {
                canvasView.setRootSplitPreview(rootDirection, theme: currentTheme)
                dragState.targetStackID = nil
                dragState.dropIntent = .splitAtRoot(rootDirection)
                paneTabDragState = dragState
                return
            }

            // Otherwise resolve directional split intent from edge distance.
            let point = targetView.convert(event.locationInWindow, from: nil)
            if let direction = PaneSplitDropIntentResolver.direction(for: point, in: targetView.bounds) {
                targetView.setSplitPreview(direction, theme: currentTheme)
                dragState.targetStackID = targetStackID
                dragState.dropIntent = .split(direction)
                paneTabDragState = dragState
                return
            }
        }

        if canPopOutPaneTab(paneID: dragState.paneID, sourceStackID: dragState.sourceStackID),
           let tearOutFrame = paneTabTearOutFrame(forWindowLocation: event.locationInWindow) {
            dragState.targetStackID = nil
            dragState.dropIntent = .tearOut(tearOutFrame)
            paneTabDragState = dragState
            return
        }

        dragState.targetStackID = nil
        dragState.dropIntent = nil
        paneTabDragState = dragState
    }

    private func endPaneTabDrag(with event: NSEvent) {
        updatePaneTabDrag(with: event)
        guard let dragState = paneTabDragState else {
            clearPaneTabSplitPreview()
            return
        }

        defer {
            dragState.ghostView?.removeFromSuperview()
            paneTabDragState = nil
            clearPaneTabSplitPreview()
            applyDeferredWorkspaceUpdateAfterPaneTabDragIfNeeded()
        }

        guard let intent = dragState.dropIntent else { return }

        switch intent {
        case .splitAtRoot(let direction):
            _ = try? controller.movePaneTabToRootSplit(
                paneID: dragState.paneID,
                sourceStackID: dragState.sourceStackID,
                direction: direction
            )
        case .split(let direction):
            guard let targetStackID = dragState.targetStackID else { return }
            _ = try? controller.movePaneTabToSplit(
                paneID: dragState.paneID,
                sourceStackID: dragState.sourceStackID,
                targetStackID: targetStackID,
                direction: direction
            )
        case .merge:
            guard let targetStackID = dragState.targetStackID else { return }
            _ = try? controller.movePaneTabToStack(
                paneID: dragState.paneID,
                sourceStackID: dragState.sourceStackID,
                targetStackID: targetStackID
            )
        case .reorder(let insertionIndex):
            guard let targetStackID = dragState.targetStackID else { return }
            _ = controller.reorderPaneTabInStack(
                paneID: dragState.paneID,
                stackID: targetStackID,
                insertionIndex: insertionIndex
            )
        case .tearOut(let frame):
            _ = controller.movePaneTabToFloatingModal(
                paneID: dragState.paneID,
                sourceStackID: dragState.sourceStackID,
                frame: frame
            )
        }
    }

    private func cancelPaneTabDrag() {
        guard let dragState = paneTabDragState else { return }
        dragState.ghostView?.removeFromSuperview()
        paneTabDragState = nil
        clearPaneTabSplitPreview()
        applyDeferredWorkspaceUpdateAfterPaneTabDragIfNeeded()
    }

    private func applyDeferredWorkspaceUpdateAfterPaneTabDragIfNeeded() {
        guard let workspace = deferredWorkspaceUpdateDuringPaneTabDrag else {
            return
        }
        deferredWorkspaceUpdateDuringPaneTabDrag = nil
        update(workspace: workspace)
    }

    private func paneStackView(atWindowLocation location: NSPoint) -> PaneStackView? {
        paneStackView(in: floatingModalOverlayView, atWindowLocation: location)
            ?? paneStackView(in: canvasView, atWindowLocation: location)
    }

    private func paneStackView(with paneStackID: PaneStackID) -> PaneStackView? {
        paneStackView(in: floatingModalOverlayView, paneStackID: paneStackID)
            ?? paneStackView(in: canvasView, paneStackID: paneStackID)
    }

    private func paneStackView(in root: NSView, atWindowLocation location: NSPoint) -> PaneStackView? {
        for subview in root.subviews.reversed() {
            if let match = paneStackView(in: subview, atWindowLocation: location) {
                return match
            }
        }
        guard let stackView = root as? PaneStackView else { return nil }
        let point = stackView.convert(location, from: nil)
        return stackView.bounds.contains(point) ? stackView : nil
    }

    private func paneStackView(in root: NSView, paneStackID: PaneStackID) -> PaneStackView? {
        if let stackView = root as? PaneStackView, stackView.paneStackID == paneStackID {
            return stackView
        }
        for subview in root.subviews.reversed() {
            if let match = paneStackView(in: subview, paneStackID: paneStackID) {
                return match
            }
        }
        return nil
    }

    private func clearPaneTabSplitPreview() {
        canvasView.clearRootSplitPreview()
        clearPaneTabSplitPreview(in: canvasView)
        clearPaneTabSplitPreview(in: floatingModalOverlayView)
    }

    private func clearPaneTabSplitPreview(in root: NSView) {
        if let stackView = root as? PaneStackView {
            stackView.clearSplitPreview()
            stackView.clearMergePreview()
        }
        root.subviews.forEach { clearPaneTabSplitPreview(in: $0) }
    }

    private func makePaneTabDragGhost(for button: NSView) -> NSView? {
        guard let contentView = button.window?.contentView else { return nil }
        let size = button.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let snapshot = NSImage(size: size, flipped: false) { [weak button] _ in
            guard let layer = button?.layer else { return false }
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            layer.render(in: ctx)
            return true
        }

        let ghost = NSImageView(image: snapshot)
        ghost.wantsLayer = true
        ghost.layer?.opacity = 0.82
        ghost.layer?.cornerRadius = 3
        ghost.layer?.shadowOpacity = 0.28
        ghost.layer?.shadowRadius = 10
        ghost.layer?.shadowColor = NSColor.black.cgColor
        ghost.layer?.shadowOffset = CGSize(width: 0, height: -3)

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        ghost.frame = buttonFrameInWindow
        contentView.addSubview(ghost, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
        return ghost
    }

    private func updatePaneTabDragGhost(_ ghost: NSView?, with event: NSEvent) {
        guard let ghost else { return }
        let cursor = event.locationInWindow
        ghost.frame.origin = NSPoint(
            x: cursor.x - ghost.frame.width / 2,
            y: cursor.y - ghost.frame.height / 2
        )
    }

    private func canPopOutPaneTab(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        allowSinglePane: Bool = false
    ) -> Bool {
        guard let workspace = currentWorkspace,
              let tab = workspace.tabs.first(where: { $0.rootLayout.paneStack(id: sourceStackID) != nil })
        else {
            return false
        }
        return PaneTabDragReadiness.canStart(
            paneID: paneID,
            sourceStackID: sourceStackID,
            in: tab,
            attachedSessionExists: controller.terminalBridge.attachedSession(for: paneID) != nil,
            allowSinglePane: allowSinglePane
        )
    }

    private func paneTabTearOutFrame(forWindowLocation location: NSPoint) -> FloatingPaneModalFrame? {
        let point = floatingModalOverlayView.convert(location, from: nil)
        let bounds = floatingModalOverlayView.bounds
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else {
            return nil
        }

        let inset = CGFloat(20)
        let defaultFrame = FloatingPaneModalFrame()
        let width = min(CGFloat(defaultFrame.width), max(320, bounds.width - inset * 2))
        let height = min(CGFloat(defaultFrame.height), max(220, bounds.height - inset * 2))
        let maxX = max(inset, bounds.width - width - inset)
        let maxY = max(inset, bounds.height - height - inset)
        let originX = min(max(point.x - width / 2, inset), maxX)
        let originY = min(max(point.y - height / 2, inset), maxY)
        return FloatingPaneModalFrame(
            x: originX,
            y: originY,
            width: width,
            height: height
        )
    }
}

private enum WorkspaceRenderUpdateKind {
    case initial
    case nonStructural
    case structural
}

private struct WorkspaceRenderReconciliationPlanner {
    private indirect enum LayoutSignature: Equatable {
        case paneStack(PaneStackID, [PaneID])
        case split(PaneSplitAxis, [LayoutSignature])
    }

    static func classify(
        previousWorkspaceID: WorkspaceID?,
        previousFocusedTabID: TabID?,
        previousLayout: TabLayoutNode?,
        nextWorkspaceID: WorkspaceID,
        nextFocusedTabID: TabID,
        nextLayout: TabLayoutNode?
    ) -> WorkspaceRenderUpdateKind {
        guard let previousWorkspaceID,
              previousWorkspaceID == nextWorkspaceID,
              let previousFocusedTabID,
              previousFocusedTabID == nextFocusedTabID,
              let previousLayout,
              let nextLayout
        else {
            return .initial
        }

        let previousSignature = signature(for: previousLayout)
        let nextSignature = signature(for: nextLayout)
        return previousSignature == nextSignature ? .nonStructural : .structural
    }

    private static func signature(for node: TabLayoutNode) -> LayoutSignature {
        switch node {
        case .paneStack(let paneStack):
            return .paneStack(paneStack.id, paneStack.panes.map(\.id))
        case .split(let axis, _, let children):
            return .split(axis, children.map(signature(for:)))
        }
    }
}

private struct PaneSplitDropIntentResolver {
    static let outerEdgeThreshold: CGFloat = 40

    static func direction(for point: NSPoint, in bounds: NSRect) -> PaneSplitDropDirection? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        let distances: [(PaneSplitDropDirection, CGFloat)] = [
            (.left, point.x - bounds.minX),
            (.right, bounds.maxX - point.x),
            (.up, bounds.maxY - point.y),
            (.down, point.y - bounds.minY),
        ]
        return distances.min { $0.1 < $1.1 }?.0
    }

    /// Returns a direction if `point` falls within the outer-edge drop zone of `bounds`.
    /// This zone triggers a root-level layout wrap regardless of which pane is under the cursor.
    /// Note: `.up` is excluded here — it is triggered by the window title bar instead.
    static func outerEdgeDirection(for point: NSPoint, in bounds: NSRect) -> PaneSplitDropDirection? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point) else { return nil }
        let t = outerEdgeThreshold
        if point.y <= bounds.minY + t { return .down }
        if point.x <= bounds.minX + t { return .left }
        if point.x >= bounds.maxX - t { return .right }
        return nil
    }
}

enum PaneTabDragReadiness {
    static func canStart(
        paneID: PaneID,
        sourceStackID: PaneStackID,
        in tab: Tab,
        attachedSessionExists: Bool,
        allowSinglePane: Bool = false
    ) -> Bool {
        guard let sourceStack = tab.rootLayout.paneStack(id: sourceStackID),
              let pane = sourceStack.panes.first(where: { $0.id == paneID })
        else {
            return false
        }

        // Don't drag if this is the only tab in the only pane stack — nothing to split into.
        if allowSinglePane == false, sourceStack.panes.count == 1, tab.rootLayout.visiblePaneIDs.count == 1 {
            return false
        }

        if let extensionPane = pane.extensionPane {
            return extensionPane.status == .ready
        }

        return pane.isTerminal && attachedSessionExists
    }
}

struct SidebarSectionAccessory {
    enum Content {
        case text(String)
        case symbol(name: String, accessibilityLabel: String)
    }

    let content: Content
    let isEnabled: Bool
    let action: () -> Void
}
