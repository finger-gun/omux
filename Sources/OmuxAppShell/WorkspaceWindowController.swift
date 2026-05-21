import AppKit
import OmuxAIStatusPlugin
import OmuxConfig
import OmuxCore
import OmuxTerminalBridge
import OmuxVault
import QuartzCore
import WebKit

private enum ShellLayoutMetrics {
    static let sidebarWidth: CGFloat = 224
    static let vaultSidebarWidth: CGFloat = 280
    static let vaultToggleSize: CGFloat = 28
    static let vaultToggleReservedWidth: CGFloat = 32
    static let outerPadding: CGFloat = 0
    static let interRegionSpacing: CGFloat = 0
    static let canvasPadding: CGFloat = 0
    static let splitSpacing: CGFloat = 1
    static let splitHitArea: CGFloat = 8
    static let paneHeaderHeight: CGFloat = 28
}

@MainActor
final class WorkspaceRootView: NSView {
    var titlebarHeightOverrideForTesting: CGFloat?
    var titlebarDoubleClickHandler: ((NSWindow) -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isInUnifiedTitlebar(event) else {
            super.mouseDown(with: event)
            return
        }

        // If the click lands on an interactive subview (e.g. a pane tab button),
        // let the normal responder chain handle it rather than initiating a window drag.
        let point = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(point), hit !== self, hit.acceptsFirstResponder || hit is NSButton || hit is NSControl {
            super.mouseDown(with: event)
            return
        }

        guard let window else {
            return
        }

        if event.clickCount >= 2 {
            if let titlebarDoubleClickHandler {
                titlebarDoubleClickHandler(window)
            } else {
                window.zoom(nil)
            }
            return
        }

        window.performDrag(with: event)
    }

    func isInUnifiedTitlebar(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        let titlebarHeight = titlebarHeightOverrideForTesting ?? safeAreaInsets.top
        guard titlebarHeight > 0 else {
            return false
        }
        return point.y >= bounds.maxY - titlebarHeight
    }

    // XCUITest determines isHittable by calling accessibilityHitTest on the
    // window at the element's centre point. Because this view returns true for
    // mouseDownCanMoveWindow, AppKit's default implementation returns self (the
    // drag surface) rather than any button subview sitting in the title bar
    // region — causing XCUITest to report those buttons as not hittable.
    //
    // Overriding here delegates to the NSView hit-test tree first; if a
    // non-self subview is found it is returned so the accessibility system
    // (and XCUITest) see the correct interactive element.
    nonisolated override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        DispatchQueue.main.sync {
            if let hit = hitTest(point), hit !== self {
                return hit.accessibilityHitTest(point)
            }
            return super.accessibilityHitTest(point)
        }
    }
}

/// A borderless button designed for the unified title bar area.
///
/// Renders as a square with slightly rounded corners and shows a visible
/// background on hover, matching the style used by VS Code title bar controls.
@MainActor
final class TitleBarButton: NSButton {
    private var isHovered = false

    private var hoverTrackingArea: NSTrackingArea?

    // NSButton inside a mouseDownCanMoveWindow container loses its default
    // accessibility role. Explicitly restore it so XCUITest can find and
    // interact with the button (isHittable == true).
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    // On headless CI runners XCUITest cannot synthesise a coordinate-based
    // click inside a mouseDownCanMoveWindow region (the title bar). It falls
    // back to accessibilityPerformPress() to determine hittability and to
    // trigger the action. NSButton's default implementation calls
    // performClick(), which requires the window to be key — a condition that
    // is not always met on headless runners. Overriding here fires the action
    // directly via sendAction, bypassing the key-window guard, so the button
    // is both considered hittable and actually activates its target/action.
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction(action, to: target)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 5), xRadius: 8, yRadius: 8)
        if isHovered {
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
        } else {
            NSColor.clear.setFill()
        }
        path.fill()
        super.draw(dirtyRect)
    }
}

@MainActor
private final class WorkspaceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WorkspaceWindowController: NSWindowController {
    private let controller: WorkspaceController
    private let rootViewController: WorkspaceShellViewController

    init(
        workspace: Workspace,
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme = .defaultTheme,
        initialPanes: OmuxConfigUI.Panes = OmuxConfigUI.Panes(),
        initialIcons: OmuxConfigUI.Icons = OmuxConfigUI.Icons(),
        vaultStore: VaultStore? = nil,
        vaultConfiguration: VaultConfiguration = VaultConfiguration(enabled: false),
        sidebarVisibilityStore: any WorkspaceSidebarVisibilityStoring = WorkspaceSidebarVisibilityStore.shared,
        onClosePaneTab: (@MainActor (PaneID) -> Void)? = nil,
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void = { _ in }
    ) {
        self.controller = controller
        self.rootViewController = WorkspaceShellViewController(
            controller: controller,
            initialTheme: initialTheme,
            initialPanes: initialPanes,
            initialIcons: initialIcons,
            vaultStore: vaultStore,
            vaultConfiguration: vaultConfiguration,
            sidebarVisibilityStore: sidebarVisibilityStore,
            onClosePaneTab: onClosePaneTab ?? { [controller] paneID in
                _ = try? controller.closePane(paneID: paneID)
            },
            onExtensionPaneAction: onExtensionPaneAction
        )
        let window = WorkspaceWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1220, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 480)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.title = workspace.name
        window.contentViewController = rootViewController
        window.setContentSize(NSSize(width: 1220, height: 780))
        window.setAccessibilityIdentifier(A11yID.mainWindow)
        super.init(window: window)
        update(workspace: workspace)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(workspace: Workspace) {
        let displayedWorkspace = controller.activeWorkspace() ?? workspace
        let presentationState = rootViewController.currentTerminalSurfacePresentationState()
        do {
            _ = try controller.ensureVisibleTerminalSurfaces(
                for: displayedWorkspace.id,
                presentationState: presentationState
            )
        } catch {
            fputs("warning: failed to ensure visible terminal surfaces: \(error)\n", stderr)
        }
        window?.title = displayedWorkspace.name
        rootViewController.update(workspace: displayedWorkspace)
    }

    func updateTheme(_ theme: WorkspaceShellTheme) {
        rootViewController.updateTheme(theme)
    }

    func vaultIndexDidUpdate() {
        rootViewController.vaultIndexDidUpdate()
    }

    func updateIcons(_ icons: OmuxConfigUI.Icons) {
        rootViewController.updateIcons(icons)
    }

    func updatePanes(_ panes: OmuxConfigUI.Panes) {
        rootViewController.updatePanes(panes)
    }

    func toggleSidebarVisibility() {
        rootViewController.toggleSidebarVisibility()
    }

    func setAgentSessionsVisibility(_ isVisible: Bool) {
        rootViewController.setVaultSidebarVisibility(isVisible)
    }

    func toggleAgentSessionsVisibility() {
        rootViewController.toggleVaultSidebar()
    }

    func presentAgentSessionsPalette(keyBindings: OpenMUXKeyBindingRegistry) {
        rootViewController.presentAgentSessionsPalette(keyBindings: keyBindings)
    }

    func presentRenameWorkspacePrompt(workspaceID: WorkspaceID? = nil) {
        rootViewController.presentRenameWorkspacePrompt(workspaceID: workspaceID)
    }

    func presentCommandPalette(initialQuery: String, keyBindings: OpenMUXKeyBindingRegistry) {
        rootViewController.presentCommandPalette(initialQuery: initialQuery, keyBindings: keyBindings)
    }

    func presentPaneFind() {
        rootViewController.presentPaneFind()
    }

    func dismissPaneFind() {
        rootViewController.dismissPaneFind()
    }

    var themeCommitHandler: ((String) -> Void)? {
        get { rootViewController.themeCommitHandler }
        set { rootViewController.themeCommitHandler = newValue }
    }
}

@MainActor
final class WorkspaceShellViewController: NSViewController {
    fileprivate enum VaultWorkspaceFilter: Equatable {
        case current
        case all
        case workspace(WorkspaceID)
    }

    private enum CachedTerminalText {
        case loaded(String?)
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
    private var vaultIndexRefreshCoordinator: VaultIndexRefreshCoordinator?
    private var vaultSourceEventWatcher: VaultSourceEventWatcher?
    private var findSearchObserverToken: UUID?
    private var collapsedWorkspaceIDs = Set<WorkspaceID>()
    private let onClosePaneTab: @MainActor (PaneID) -> Void
    private let onExtensionPaneAction: @MainActor (ExtensionPaneActionRequest) -> Void

    private var floatingModalOverlayView: FloatingModalOverlayView {
        shellOverlayHostView.floatingModalOverlayView
    }

    var themeCommitHandler: ((String) -> Void)?

    init(
        controller: WorkspaceController,
        initialTheme: WorkspaceShellTheme,
        initialPanes: OmuxConfigUI.Panes,
        initialIcons: OmuxConfigUI.Icons,
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
        self.vaultStore = vaultStore
        self.vaultConfiguration = vaultConfiguration
        self.sidebarVisibilityStore = sidebarVisibilityStore
        self.isSidebarVisible = sidebarVisibilityStore.isSidebarVisible
        self.onClosePaneTab = onClosePaneTab
        self.onExtensionPaneAction = onExtensionPaneAction
        super.init(nibName: nil, bundle: nil)
        configureVaultSourceIndexing()
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
        vaultToggleButton.image = NSImage(systemSymbolName: "sidebar.squares.right", accessibilityDescription: "Toggle Agent Sessions")
        vaultToggleButton.identifier = NSUserInterfaceItemIdentifier(A11yID.vaultSidebarToggle.rawValue)
        vaultToggleButton.setAccessibilityIdentifier(A11yID.vaultSidebarToggle)
        vaultToggleButton.toolTip = "Toggle Agent Sessions (⇧⌘B)"
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
        if vaultConfiguration.enabled {
            view.addSubview(vaultSidebarView)
            if vaultConfiguration.collapsedToggleVisible {
                view.addSubview(vaultToggleButton)
            }
        }
        view.addSubview(shellOverlayHostView)

        let sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.sidebarWidth)
        let vaultSidebarWidthConstraint = vaultConfiguration.enabled
            ? vaultSidebarView.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultSidebarWidth)
            : nil
        let mainColumnLeadingConstraint = mainColumn.leadingAnchor.constraint(
            equalTo: sidebarView.trailingAnchor,
            constant: ShellLayoutMetrics.interRegionSpacing
        )
        let mainColumnTrailingConstraint = vaultConfiguration.enabled
            ? mainColumn.trailingAnchor.constraint(
                equalTo: vaultSidebarView.leadingAnchor,
                constant: -ShellLayoutMetrics.interRegionSpacing
            )
            : mainColumn.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -ShellLayoutMetrics.outerPadding - reservedWidthForCollapsedVaultToggle
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

        if vaultConfiguration.enabled, let vaultSidebarWidthConstraint {
            constraints += [
                vaultSidebarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                vaultSidebarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                vaultSidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                vaultSidebarWidthConstraint,
            ]
            if vaultConfiguration.collapsedToggleVisible {
                constraints += [
                    vaultToggleButton.centerYAnchor.constraint(equalTo: titleBarGuide.centerYAnchor),
                    vaultToggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                    vaultToggleButton.widthAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultToggleSize),
                    vaultToggleButton.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.vaultToggleSize),
                ]
            }
        }

        // Sidebar toggle button: always present, positioned to the left of the
        // vault toggle (or at the trailing edge when vault is disabled).
        let sidebarButtonTrailing = vaultConfiguration.enabled && vaultConfiguration.collapsedToggleVisible
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
        if let workspace = controller.activeWorkspace() ?? currentWorkspace { update(workspace: workspace) }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard windowIsKey else {
            return
        }
        windowIsKey = false
        if let workspace = controller.activeWorkspace() ?? currentWorkspace { update(workspace: workspace) }
    }

    @objc private func windowPresentationStateDidChange(_ notification: Notification) {
        _ = notification
        if let workspace = controller.activeWorkspace() ?? currentWorkspace {
            update(workspace: workspace)
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
            update(workspace: workspace)
        }
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
        currentWorkspace = workspace
        let focusedPaneID = workspace.focusedPane?.id
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
        let scopedVaultSessions = vaultSessions(for: normalizedWorkspaceFilter, activeWorkspace: workspace, allWorkspaces: allWorkspaces)
        pruneActiveVaultSessionBindings(allWorkspaces: allWorkspaces)
        let workspaceFilterItems = vaultWorkspaceFilterItems(activeWorkspace: workspace, allWorkspaces: allWorkspaces)
        sidebarView.render(
            workspaceItems: workspaceItems,
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
            }
        )
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
            }
        )
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

    private func invalidateIconCacheForChangedPaths(from previousWorkspace: Workspace?, to workspace: Workspace) {
        guard let previousWorkspace else {
            return
        }

        let previousPaths = Dictionary(
            uniqueKeysWithValues: previousWorkspace.tabs
                .flatMap(\.panes)
                .map { ($0.id, iconResolutionPath(for: $0)) }
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

    private func iconResolutionPath(for pane: Pane) -> String {
        pane.terminalState.reportedWorkingDirectory
            ?? pane.terminalSession?.workingDirectory
            ?? pane.extensionPane?.source
            ?? pane.id.rawValue
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
                update(workspace: workspace)
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
                    self.update(workspace: workspace)
                }
            } catch {
                if let self, self.vaultLoadGeneration == generation {
                    self.vaultIsLoading = false
                    if let workspace = self.currentWorkspace {
                        self.update(workspace: workspace)
                    }
                }
                fputs("Agent Sessions list failed: \(error)\n", stderr)
            }
        }
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
                self.update(workspace: workspace)
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
            update(workspace: workspace)
        }
    }

    private func resumeVaultSession(_ sessionID: String) {
        let allWorkspaces = controller.allWorkspaces()
        pruneActiveVaultSessionBindings(allWorkspaces: allWorkspaces)
        if let activePaneID = activePaneID(forVaultSession: sessionID, allWorkspaces: allWorkspaces, sessions: vaultSessions) {
            _ = controller.focus(paneID: activePaneID)
            return
        }
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
                let connectedPaths = self.currentWorkspace.map { self.vaultConnectedPaths(for: $0) } ?? []
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
            update(workspace: workspace)
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
        let alert = NSAlert()
        alert.messageText = "Delete Agent Session"
        alert.informativeText = "This removes the indexed session from OpenMUX."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let performDelete = { [weak self] in
            self?.deleteVaultSession(sessionID: sessionID)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    performDelete()
                }
            }
            return
        }
        if alert.runModal() == .alertFirstButtonReturn {
            performDelete()
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

    private func applyVaultSidebarVisibility() {
        let isVisible = vaultConfiguration.enabled && isVaultSidebarVisible
        vaultSidebarView.isHidden = !isVisible
        vaultToggleButton.isHidden = !vaultConfiguration.enabled || !vaultConfiguration.collapsedToggleVisible
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
            let connectedPaths = vaultConnectedPaths(for: activeWorkspace)
            return vaultSessions.filter {
                Self.vaultPathMatches($0.workingDirectory, connectedPaths: connectedPaths)
            }
        case .workspace(let workspaceID):
            guard let workspace = allWorkspaces.first(where: { $0.id == workspaceID }) else {
                let connectedPaths = vaultConnectedPaths(for: activeWorkspace)
                return vaultSessions.filter {
                    Self.vaultPathMatches($0.workingDirectory, connectedPaths: connectedPaths)
                }
            }

            let connectedPaths = vaultConnectedPaths(for: workspace)
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
            let includedAgents = vaultConfiguration.includedAgents.filter { $0 != .custom }
            agentCount = max(1, includedAgents.count)
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

    private func vaultConnectedPaths(for workspace: Workspace) -> [String] {
        let panes = workspace.tabs.flatMap(\.panes) + workspace.floatingPaneModals.flatMap(\.panes)
        let panePaths = panes.compactMap { pane in
            (pane.terminalState.reportedWorkingDirectory ?? pane.terminalSession?.workingDirectory)
                .flatMap(Self.standardizedVaultPath)
        }

        let scopePaths = Self.workspaceScopePaths(from: panePaths)
        if scopePaths.isEmpty == false {
            return Array(Set(scopePaths)).sorted { $0.count < $1.count }
        }

        return [workspace.rootPath].compactMap(Self.standardizedVaultPath)
    }

    private static func workspaceScopePaths(from panePaths: [String]) -> [String] {
        let roots = panePaths.map(projectLikeRoot)
        let counts = roots.reduce(into: [String: Int]()) { result, root in
            result[root, default: 0] += 1
        }
        guard let maxCount = counts.values.max(), maxCount > 1 else {
            return Array(Set(roots)).sorted { $0.count < $1.count }
        }
        return counts
            .filter { $0.value == maxCount }
            .map(\.key)
            .sorted { $0.count < $1.count }
    }

    private static func projectLikeRoot(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.standardizedFileURL.pathComponents
        let markers: Set<String> = ["projects", "project", "src", "source", "workspace", "workspaces", "developer"]
        guard let markerIndex = components.firstIndex(where: { markers.contains($0.lowercased()) }),
              markerIndex + 2 < components.count
        else {
            return path
        }

        let rootComponents = Array(components.prefix(markerIndex + 3))
        return NSString.path(withComponents: rootComponents)
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
            if normalized.contains("claude") {
                return .claude
            }
            if normalized.contains("opencode") {
                return .opencode
            }
            if normalized.contains("rovodev") || normalized.contains("rovo dev") {
                return .rovodev
            }
            if normalized == "pi" || normalized.contains(" pi ") {
                return .pi
            }
        }

        return nil
    }

    private static func standardizedVaultPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
            .standardizedFileURL
            .path
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
                        return SidebarItem(
                            kind: .terminal,
                            identifier: pane.id.rawValue,
                            icon: renderedIcon(for: metadata.icon, pointSize: 11, weight: .medium),
                            progress: pane.terminalState.progress,
                            title: metadata.title,
                            subtitle: metadata.subtitle,
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

        let alert = NSAlert()
        alert.messageText = "Rename Workspace"
        alert.informativeText = "Choose a new name for this workspace."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: workspace.customName ?? workspace.name)
        nameField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = nameField

        let rename = { [weak self] in
            guard let self else { return }
            do {
                _ = try controller.renameWorkspace(workspace.id, to: nameField.stringValue)
            } catch {
                assertionFailure("Failed to rename workspace: \(error)")
            }
        }

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    rename()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            rename()
        }
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
                var commands = CommandPaletteCommandCatalog.commands(
                    controller: controller,
                    keyBindings: keyBindings,
                    subtitleOverrides: configOpenContext.map { ["cli:omux.config.open": $0.subtitle] } ?? [:]
                )
                if vaultConfiguration.enabled && vaultStore != nil {
                    commands.append(vaultSessionsCommand(keyBindings: keyBindings))
                }
                return CommandPaletteSearch.commandResults(
                    query: parsed.matchingText,
                    commands: commands
                )
            }
        }

        var themeBeforeSubPalette: WorkspaceShellTheme? = nil

        paletteView.invokeResult = { [weak self] result in
            guard let self else { return .failed("Window is unavailable") }
            if result.invocationTarget == .action(.sidebarToggle) {
                toggleSidebarVisibility()
                return .invoked
            }
            if result.invocationTarget == .action(.agentSessionsToggle) {
                toggleVaultSidebar()
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
            if result.invocationTarget == .vaultSessions {
                presentVaultSessionsSubPalette(in: paletteView)
                return .inert
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
            if self?.vaultPaletteSessions.contains(where: { $0.id == identifier }) == true {
                self?.resumeVaultSession(identifier)
                return
            }
            themeBeforeSubPalette = nil
            self?.themeCommitHandler?(identifier)
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
            if let paletteView {
                self?.shellOverlayHostView.dismiss(commandPaletteView: paletteView)
            }
        }
        paletteView.present(initialQuery: initialQuery, restoring: previousResponder)
    }

    func presentAgentSessionsPalette(keyBindings: OpenMUXKeyBindingRegistry) {
        presentCommandPalette(initialQuery: ">", keyBindings: keyBindings)
        if let paletteView = commandPaletteView {
            presentVaultSessionsSubPalette(in: paletteView)
        }
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

    private func vaultSessionsCommand(keyBindings: OpenMUXKeyBindingRegistry) -> CommandPaletteCommand {
        _ = keyBindings
        return CommandPaletteCommand(
            id: "builtin:agent-sessions",
            title: "Agent Sessions",
            subtitle: "Resume an indexed agent session",
            category: .action,
            matchText: "agent sessions history resume codex copilot",
            aliases: ["resume session", "codex sessions", "copilot sessions"],
            requiresArguments: false,
            hasSafeDefaultTarget: true,
            invocationTarget: .vaultSessions
        )
    }

    private func presentVaultSessionsSubPalette(in paletteView: CommandPaletteView) {
        vaultPaletteSessions = []
        vaultPaletteEntries = []
        paletteView.enterVaultSessionsSubPalette { [weak self] query in
            self?.vaultPaletteResults(query: query) ?? []
        }
        loadVaultPaletteSessions(paletteView: paletteView)
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
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Set a custom tab name. Leave empty to clear the custom name."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: currentTitle)
        nameField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = nameField

        let rename = { [weak self] in
            guard let self else { return }
            let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                _ = try? controller.clearPaneAlias(paneID)
            } else {
                _ = try? controller.setPaneAlias(paneID, to: trimmed)
            }
        }

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    rename()
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            rename()
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
        let bounds = floatingModalOverlayView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let threshold = PaneSplitDropIntentResolver.outerEdgeThreshold
        let candidates: [(PaneSplitDropDirection, CGFloat)] = [
            (.left, frame.minX),
            (.right, bounds.maxX - frame.maxX),
            (.up, frame.minY),
            (.down, bounds.maxY - frame.maxY),
        ].filter { $0.1 <= threshold }

        return candidates.min { $0.1 < $1.1 }?.0
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

struct SidebarItem {
    enum Kind {
        case workspace
        case terminal
    }

    enum Action {
        case workspace(WorkspaceID)
        case pane(PaneID)
    }

    let kind: Kind
    let identifier: String
    let icon: OmuxRenderedIcon?
    let progress: PaneProgress?
    let title: String
    let subtitle: String?
    let isActive: Bool
    let isExpanded: Bool?
    let action: Action
    let contextMenuProvider: (() -> NSMenu)?

    init(
        kind: Kind,
        identifier: String,
        icon: OmuxRenderedIcon?,
        progress: PaneProgress?,
        title: String,
        subtitle: String?,
        isActive: Bool,
        isExpanded: Bool? = nil,
        action: Action,
        contextMenuProvider: (() -> NSMenu)?
    ) {
        self.kind = kind
        self.identifier = identifier
        self.icon = icon
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
        self.isExpanded = isExpanded
        self.action = action
        self.contextMenuProvider = contextMenuProvider
    }

    var workspaceID: WorkspaceID? {
        guard case .workspace(let workspaceID) = action else {
            return nil
        }
        return workspaceID
    }

    var rowHeight: CGFloat {
        switch kind {
        case .workspace:
            return 28
        case .terminal:
            return subtitle == nil ? 26 : 34
        }
    }
}

private struct SidebarSectionAccessory {
    enum Content {
        case text(String)
        case symbol(name: String, accessibilityLabel: String)
    }

    let content: Content
    let isEnabled: Bool
    let action: () -> Void
}

@MainActor
final class WorkspaceSidebarView: NSView {
    private let workspacesSection = WorkspaceSidebarSectionView()
    private let scrollView = NSScrollView()
    private let updateNoticeView = SidebarUpdateNoticeView()
    private let container = NSStackView()
    private let scrollContent = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityElement(true)

        container.orientation = .vertical
        container.alignment = .leading
        container.distribution = .fill
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.orientation = .vertical
        scrollContent.alignment = .leading
        scrollContent.distribution = .fill
        scrollContent.spacing = 10
        scrollContent.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = scrollContent
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let header = workspacesSection.headerView
        header.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(container)
        scrollContent.addArrangedSubview(workspacesSection)
        container.addArrangedSubview(scrollView)
        container.addArrangedSubview(updateNoticeView)
        updateNoticeView.isHidden = true

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            container.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            scrollView.widthAnchor.constraint(equalTo: container.widthAnchor),
            updateNoticeView.widthAnchor.constraint(equalTo: container.widthAnchor),
            scrollContent.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            scrollContent.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            scrollContent.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor, constant: -12),
            scrollContent.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            workspacesSection.widthAnchor.constraint(equalTo: scrollContent.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.sidebarBackground.cgColor
        layer?.borderWidth = 0
        // Draw a 1px right-edge separator matching the VSCode style
        let rightBorder = layer?.sublayers?.first(where: { $0.name == "sidebarRightBorder" }) ?? {
            let l = CALayer()
            l.name = "sidebarRightBorder"
            layer?.addSublayer(l)
            return l
        }()
        rightBorder.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        rightBorder.frame = CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        rightBorder.autoresizingMask = [.layerMinXMargin, .layerHeightSizable]
        workspacesSection.apply(theme: theme)
        updateNoticeView.apply(theme: theme)
    }

    func render(
        workspaceItems: [SidebarItem],
        theme: WorkspaceShellTheme,
        onSelectWorkspace: @escaping @MainActor (WorkspaceID) -> Void,
        onCreateWorkspace: @escaping @MainActor () -> Void,
        onDeleteWorkspace: @escaping @MainActor () -> Void,
        canDeleteWorkspace: Bool,
        updateAvailability: OpenMUXUpdateAvailability?,
        onMoveWorkspace: @escaping @MainActor (WorkspaceID, Int) -> Void,
        onToggleWorkspaceExpansion: @escaping @MainActor (WorkspaceID) -> Void,
        onRenameWorkspace: @escaping @MainActor (WorkspaceID, String) -> Void,
        onSelectPane: @escaping @MainActor (PaneID) -> Void
    ) {
        apply(theme: theme)

        workspacesSection.renderButtons(
            items: workspaceItems,
            title: "WORKSPACES",
            count: workspaceItems.filter { $0.kind == .workspace }.count,
            emptyState: "No workspaces open",
            theme: theme,
            accessories: [
                SidebarSectionAccessory(
                    content: .symbol(name: "plus", accessibilityLabel: "Create workspace"),
                    isEnabled: true,
                    action: onCreateWorkspace
                ),
            ],
            onMoveWorkspace: onMoveWorkspace,
            onToggleWorkspaceExpansion: onToggleWorkspaceExpansion,
            onRenameWorkspace: onRenameWorkspace,
            buttonHandler: { item in
                switch item.action {
                case .workspace(let workspaceID):
                    onSelectWorkspace(workspaceID)
                case .pane(let paneID):
                    onSelectPane(paneID)
                }
            }
        )
        updateNoticeView.render(updateAvailability: updateAvailability)
    }

    var updateNoticeTextForTesting: String? {
        updateNoticeView.noticeTextForTesting
    }
}

@MainActor
private final class SidebarUpdateNoticeView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let commandLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        commandLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        titleLabel.maximumNumberOfLines = 2
        commandLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        commandLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(commandLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            commandLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            commandLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            commandLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            commandLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        titleLabel.textColor = theme.shell.textPrimary
        commandLabel.textColor = theme.shell.textMuted
        layer?.backgroundColor = theme.shell.canvasBackground.cgColor
    }

    func render(updateAvailability: OpenMUXUpdateAvailability?) {
        guard let updateAvailability else {
            isHidden = true
            titleLabel.stringValue = ""
            commandLabel.stringValue = ""
            return
        }

        isHidden = false
        titleLabel.stringValue = "New version \(updateAvailability.version)"
        commandLabel.stringValue = "run: omux update"
    }

    var noticeTextForTesting: String? {
        guard isHidden == false else {
            return nil
        }
        return "\(titleLabel.stringValue) \(commandLabel.stringValue)"
    }
}

@MainActor
private final class WorkspaceSidebarSectionView: NSView {
    private struct WorkspaceDragGroup {
        let workspaceID: WorkspaceID
        var buttons: [SidebarItemButton]
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let itemStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var accessoryButtons: [ChromePillButton] = []
    private var itemButtons: [SidebarItemButton] = []
    private var workspaceButtons: [SidebarItemButton] = []
    private var workspaceDragGroups: [WorkspaceDragGroup] = []
    private var currentTheme: WorkspaceShellTheme?
    private var reorderHandler: ((WorkspaceID, Int) -> Void)?
    private var draggingWorkspaceID: WorkspaceID?

    /// The header row (title + accessory buttons). Lives outside the scroll view
    /// so it stays visible and receives mouse events regardless of scroll position.
    let headerView = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        headerView.orientation = .horizontal
        headerView.alignment = .centerY
        headerView.translatesAutoresizingMaskIntoConstraints = false

        itemStack.orientation = .vertical
        itemStack.alignment = .leading
        itemStack.spacing = 2
        itemStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        emptyLabel.font = .systemFont(ofSize: 11, weight: .regular)
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        headerView.addArrangedSubview(titleLabel)
        headerView.addArrangedSubview(NSView())

        addSubview(itemStack)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            itemStack.topAnchor.constraint(equalTo: topAnchor),
            itemStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            itemStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            itemStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: topAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        titleLabel.textColor = theme.shell.textMuted
        emptyLabel.textColor = theme.shell.textMuted
        accessoryButtons.forEach { $0.applyTheme(theme) }
    }

    func renderButtons(
        items: [SidebarItem],
        title: String,
        count: Int,
        emptyState: String,
        theme: WorkspaceShellTheme,
        accessories: [SidebarSectionAccessory],
        onMoveWorkspace: @escaping (WorkspaceID, Int) -> Void,
        onToggleWorkspaceExpansion: @escaping (WorkspaceID) -> Void,
        onRenameWorkspace: @escaping (WorkspaceID, String) -> Void,
        buttonHandler: @escaping (SidebarItem) -> Void
    ) {
        titleLabel.stringValue = "\(title) · \(count)"
        emptyLabel.stringValue = emptyState
        currentTheme = theme
        reorderHandler = onMoveWorkspace
        draggingWorkspaceID = nil

        for button in itemButtons {
            itemStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        itemButtons.removeAll()
        workspaceButtons.removeAll()
        workspaceDragGroups.removeAll()

        for accessoryButton in accessoryButtons {
            headerView.removeArrangedSubview(accessoryButton)
            accessoryButton.removeFromSuperview()
        }
        accessoryButtons.removeAll()
        for accessory in accessories {
            let button = ChromePillButton()
            switch accessory.content {
            case .text(let title):
                button.configure(title: title, active: false, theme: theme, compact: true)
            case .symbol(let name, let accessibilityLabel):
                button.configure(symbolName: name, accessibilityLabel: accessibilityLabel, active: false, theme: theme, compact: true)
            }
            button.isEnabled = accessory.isEnabled
            button.onPress = accessory.action
            accessoryButtons.append(button)
            headerView.addArrangedSubview(button)
        }

        emptyLabel.isHidden = !items.isEmpty
        itemStack.isHidden = items.isEmpty

        for item in items {
            let button = SidebarItemButton()
            button.configure(item: item, theme: theme)
            button.onPress = {
                buttonHandler(item)
            }
            button.onToggleExpansion = {
                if let workspaceID = item.workspaceID {
                    onToggleWorkspaceExpansion(workspaceID)
                }
            }
            button.contextMenuProvider = item.contextMenuProvider
            if let workspaceID = item.workspaceID {
                button.workspaceID = workspaceID
                button.onRename = { newName in
                    onRenameWorkspace(workspaceID, newName)
                }
                button.onBeginRename = { [weak button] in
                    button?.beginInlineRename()
                }
                // Override context menu to wire Rename… to inline rename
                let itemProvider = item.contextMenuProvider
                button.contextMenuProvider = { [weak button] in
                    guard let menu = itemProvider?() else { return nil }
                    if let renameItem = menu.item(withTitle: "Rename…") {
                        renameItem.onSelect { [weak button] in
                            button?.beginInlineRename()
                        }
                    }
                    return menu
                }
                workspaceButtons.append(button)
                workspaceDragGroups.append(WorkspaceDragGroup(workspaceID: workspaceID, buttons: [button]))
                button.onDragStarted = { [weak self] button, _ in
                    self?.beginWorkspaceDrag(for: button)
                }
                button.onDragMoved = { [weak self] button, event in
                    self?.updateWorkspaceDrag(for: button, with: event)
                }
                button.onDragEnded = { [weak self] button, _ in
                    self?.finishWorkspaceDrag(for: button)
                }
            } else {
                button.workspaceID = nil
                button.onDragStarted = nil
                button.onDragMoved = nil
                button.onDragEnded = nil
                if let lastGroupIndex = workspaceDragGroups.indices.last {
                    workspaceDragGroups[lastGroupIndex].buttons.append(button)
                }
            }
            itemStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: item.rowHeight).isActive = true
            itemButtons.append(button)
        }
    }

    private func beginWorkspaceDrag(for button: SidebarItemButton) {
        draggingWorkspaceID = button.workspaceID
        updateWorkspaceDragAppearance()
    }

    private func updateWorkspaceDrag(for button: SidebarItemButton, with event: NSEvent) {
        guard draggingWorkspaceID == button.workspaceID else {
            return
        }

        guard let targetIndex = workspaceInsertionIndex(for: event) else {
            return
        }

        previewWorkspaceDrag(toWorkspaceIndex: targetIndex)
        updateWorkspaceDragAppearance()
    }

    private func finishWorkspaceDrag(for button: SidebarItemButton) {
        defer {
            draggingWorkspaceID = nil
            updateWorkspaceDragAppearance()
        }

        guard let workspaceID = button.workspaceID,
              let targetIndex = workspaceDragGroups.firstIndex(where: { $0.workspaceID == workspaceID })
        else {
            return
        }

        reorderHandler?(workspaceID, targetIndex)
    }

    private func workspaceInsertionIndex(for event: NSEvent) -> Int? {
        guard let draggingWorkspaceID else {
            return nil
        }

        let candidateButtons = workspaceButtons.filter { $0.workspaceID != draggingWorkspaceID }
        for (index, button) in candidateButtons.enumerated() {
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            if event.locationInWindow.y >= center.y {
                return index
            }
        }
        return candidateButtons.count
    }

    private func updateWorkspaceDragAppearance() {
        for group in workspaceDragGroups {
            let isDraggingGroup = group.workspaceID == draggingWorkspaceID
            for button in group.buttons {
                button.alphaValue = isDraggingGroup ? 0.72 : 1
                button.setDropTarget(false, theme: currentTheme)
            }
            group.buttons.first?.setDraggingPreview(isDraggingGroup, theme: currentTheme)
        }
    }

    private func previewWorkspaceDrag(toWorkspaceIndex targetIndex: Int) {
        guard let draggingWorkspaceID,
              let currentIndex = workspaceDragGroups.firstIndex(where: { $0.workspaceID == draggingWorkspaceID }),
              targetIndex >= workspaceDragGroups.startIndex,
              targetIndex <= workspaceDragGroups.endIndex - 1,
              currentIndex != targetIndex
        else {
            return
        }

        let group = workspaceDragGroups.remove(at: currentIndex)
        workspaceDragGroups.insert(group, at: targetIndex)
        workspaceButtons = workspaceDragGroups.compactMap { group in
            group.buttons.first { $0.workspaceID == group.workspaceID }
        }

        let arrangedButtons = workspaceDragGroups.flatMap(\.buttons)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.allowsImplicitAnimation = true
            for button in arrangedButtons {
                itemStack.removeArrangedSubview(button)
            }
            for (index, button) in arrangedButtons.enumerated() {
                itemStack.insertArrangedSubview(button, at: index)
            }
            itemStack.layoutSubtreeIfNeeded()
        }
    }
}

@MainActor
private final class VaultWorkspaceFilterBox {
    let filter: WorkspaceShellViewController.VaultWorkspaceFilter

    init(_ filter: WorkspaceShellViewController.VaultWorkspaceFilter) {
        self.filter = filter
    }
}

@MainActor
private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private extension NSColor {
    var omuxIsDark: Bool {
        let color = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) ?? self
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5
    }
}

@MainActor
private final class WorkspaceVaultSidebarView: NSView, NSSearchFieldDelegate {
    struct WorkspaceFilterItem {
        let title: String
        let filter: WorkspaceShellViewController.VaultWorkspaceFilter
    }

    struct SessionActivity: Equatable {
        let isActive: Bool
        let progress: PaneProgress
    }

    private struct SessionRowState: Equatable {
        let session: VaultSessionSummary
        let activity: SessionActivity?
    }

    private let titleLabel = NSTextField(labelWithString: "AGENT SESSIONS")
    private let refreshButton = NSButton()
    private let searchContainer = NSView()
    private let searchIcon = NSImageView()
    private let searchField = AgentSessionsSearchField()
    private let filterRow = NSStackView()
    private let agentPopup = NSPopUpButton()
    private let workspacePopup = NSPopUpButton()
    private let scrollView = NSScrollView()
    private let stack = FlippedStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var onToggle: (() -> Void)?
    private var onRefresh: (() -> Void)?
    private var onSearchChanged: ((String) -> Void)?
    private var onAgentFilterChanged: ((VaultAgentKind?) -> Void)?
    private var onWorkspaceFilterChanged: ((WorkspaceShellViewController.VaultWorkspaceFilter) -> Void)?
    private var onNeedsMore: (() -> Void)?
    private var onResume: ((String) -> Void)?
    private var onDelete: ((String) -> Void)?
    private var currentTheme = WorkspaceShellTheme.defaultTheme
    private var renderedRows: [SessionRowState] = []
    private var renderedEmptyMessage: String?
    private var isSearchFocused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityElement(true)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshButton.isBordered = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Agent Sessions")
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 14
        searchContainer.layer?.borderWidth = 1
        searchContainer.translatesAutoresizingMaskIntoConstraints = false

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.setContentHuggingPriority(.required, for: .horizontal)

        searchField.font = .systemFont(ofSize: 14, weight: .regular)
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.backgroundColor = .clear
        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        filterRow.orientation = .horizontal
        filterRow.alignment = .centerY
        filterRow.distribution = .fillEqually
        filterRow.spacing = 6
        filterRow.translatesAutoresizingMaskIntoConstraints = false

        agentPopup.isBordered = false
        agentPopup.target = self
        agentPopup.action = #selector(agentFilterChanged)
        agentPopup.translatesAutoresizingMaskIntoConstraints = false
        rebuildAgentMenu(availableAgents: [], selectedAgent: nil)

        workspacePopup.isBordered = false
        workspacePopup.target = self
        workspacePopup.action = #selector(workspaceFilterChanged)
        workspacePopup.translatesAutoresizingMaskIntoConstraints = false
        rebuildWorkspaceMenu(items: [], selectedFilter: .current)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = stack
        scrollView.contentView.postsBoundsChangedNotifications = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(refreshButton)
        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)
        filterRow.addArrangedSubview(workspacePopup)
        filterRow.addArrangedSubview(agentPopup)
        addSubview(header)
        addSubview(searchContainer)
        addSubview(filterRow)
        addSubview(scrollView)
        addSubview(statusLabel)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            refreshButton.widthAnchor.constraint(equalToConstant: 22),
            refreshButton.heightAnchor.constraint(equalToConstant: 22),
            searchContainer.heightAnchor.constraint(equalToConstant: 28),
            searchContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchIcon.heightAnchor.constraint(equalToConstant: 14),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 7),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.heightAnchor.constraint(equalTo: searchContainer.heightAnchor),
            filterRow.heightAnchor.constraint(equalToConstant: 24),
            filterRow.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 6),
            filterRow.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            filterRow.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),
            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    // Keep the accessibility element flag in sync with visibility so that
    // XCUITest's `exists` predicate returns `false` when the sidebar is hidden.
    override var isHidden: Bool {
        didSet { setAccessibilityElement(!isHidden) }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var isFlipped: Bool { true }

    func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        layer?.backgroundColor = theme.shell.sidebarBackground.cgColor
        let leftBorder = layer?.sublayers?.first(where: { $0.name == "vaultSidebarLeftBorder" }) ?? {
            let l = CALayer()
            l.name = "vaultSidebarLeftBorder"
            layer?.addSublayer(l)
            return l
        }()
        leftBorder.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        leftBorder.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
        leftBorder.autoresizingMask = [.layerMaxXMargin, .layerHeightSizable]
        titleLabel.textColor = theme.shell.textMuted
        refreshButton.contentTintColor = theme.shell.textMuted
        workspacePopup.contentTintColor = theme.shell.textMuted
        agentPopup.contentTintColor = theme.shell.textMuted
        statusLabel.textColor = theme.shell.textMuted
        applySearchFieldTheme()
        applyFilterMenuTheme()
        for case let row as VaultSessionRowButton in stack.arrangedSubviews {
            row.apply(theme: theme)
        }
    }

    private func applySearchFieldTheme() {
        let colors = currentTheme.shell
        searchField.textColor = colors.textPrimary
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [
                .foregroundColor: colors.textMuted,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            ]
        )
        searchIcon.contentTintColor = colors.textMuted
        searchContainer.layer?.backgroundColor = colors.paneCardBackground.cgColor
        searchContainer.layer?.borderColor = (isSearchFocused ? colors.accent : colors.subduedBorder).cgColor
    }

    private func applyFilterMenuTheme() {
        let colors = currentTheme.shell
        let appearance = NSAppearance(named: colors.sidebarBackground.omuxIsDark ? .darkAqua : .aqua)
        let itemAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.textPrimary,
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: colors.textMuted,
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        ]
        for popup in [workspacePopup, agentPopup] {
            popup.appearance = appearance
            popup.menu?.appearance = appearance
            popup.contentTintColor = colors.textMuted
            if let title = popup.titleOfSelectedItem {
                popup.attributedTitle = NSAttributedString(string: title, attributes: selectedAttributes)
            }
            popup.itemArray.forEach { item in
                item.attributedTitle = NSAttributedString(string: item.title, attributes: itemAttributes)
            }
        }
    }

    func render(
        sessions: [VaultSessionSummary],
        searchQuery: String,
        selectedAgent: VaultAgentKind?,
        availableAgents: Set<VaultAgentKind>,
        workspaceFilter: WorkspaceShellViewController.VaultWorkspaceFilter,
        workspaceFilterItems: [WorkspaceFilterItem],
        isLoading: Bool,
        hasMore: Bool,
        sessionActivityByID: [String: SessionActivity],
        theme: WorkspaceShellTheme,
        onToggle: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSearchChanged: @escaping (String) -> Void,
        onAgentFilterChanged: @escaping (VaultAgentKind?) -> Void,
        onWorkspaceFilterChanged: @escaping (WorkspaceShellViewController.VaultWorkspaceFilter) -> Void,
        onNeedsMore: @escaping () -> Void,
        onResume: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void
    ) {
        self.onToggle = onToggle
        self.onRefresh = onRefresh
        self.onSearchChanged = onSearchChanged
        self.onAgentFilterChanged = onAgentFilterChanged
        self.onWorkspaceFilterChanged = onWorkspaceFilterChanged
        self.onNeedsMore = onNeedsMore
        self.onResume = onResume
        self.onDelete = onDelete
        if searchField.stringValue != searchQuery {
            searchField.stringValue = searchQuery
        }
        rebuildWorkspaceMenu(items: workspaceFilterItems, selectedFilter: workspaceFilter)
        rebuildAgentMenu(availableAgents: availableAgents, selectedAgent: selectedAgent)
        let scrollOrigin = scrollView.contentView.bounds.origin
        let shouldPreserveScroll = scrollView.documentView === stack && stack.frame.height > scrollView.contentView.bounds.height
        if sessions.isEmpty {
            let emptyMessage = emptyStateMessage(
                isLoading: isLoading,
                workspaceFilter: workspaceFilter,
                workspaceFilterItems: workspaceFilterItems,
                selectedAgent: selectedAgent,
                searchQuery: searchQuery
            )
            if renderedRows.isEmpty == false || renderedEmptyMessage != emptyMessage {
                clearSessionRows()
                renderedRows = []
                renderedEmptyMessage = emptyMessage
                let empty = NSTextField(labelWithString: emptyMessage)
                empty.font = .systemFont(ofSize: 11)
                empty.textColor = theme.shell.textMuted
                empty.maximumNumberOfLines = 2
                stack.addArrangedSubview(empty)
            }
        } else {
            let nextRows = Self.visibleRows(sessions: sessions, sessionActivityByID: sessionActivityByID)
            if renderedRows != nextRows {
                clearSessionRows()
                renderedRows = nextRows
                renderedEmptyMessage = nil
                for rowState in nextRows {
                    let row = VaultSessionRowButton(session: rowState.session, activity: rowState.activity)
                    row.apply(theme: theme)
                    row.onOpen = { [weak self] id in self?.onResume?(id) }
                    row.onDelete = { [weak self] id in self?.onDelete?(id) }
                    stack.addArrangedSubview(row)
                    row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                }
            }
        }
        if isLoading {
            statusLabel.stringValue = sessions.isEmpty ? "Loading..." : "Refreshing..."
        } else if hasMore {
            statusLabel.stringValue = "Scroll for more"
        } else {
            statusLabel.stringValue = sessions.isEmpty ? "" : "\(sessions.count) sessions"
        }
        apply(theme: theme)
        restoreScrollOriginIfNeeded(scrollOrigin, preserve: shouldPreserveScroll)
    }

    private func clearSessionRows() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func restoreScrollOriginIfNeeded(_ origin: NSPoint, preserve: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stack.layoutSubtreeIfNeeded()
            let contentHeight = self.stack.frame.height
            let visibleHeight = self.scrollView.contentView.bounds.height
            guard contentHeight > visibleHeight + 1 else {
                self.scrollView.contentView.scroll(to: .zero)
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
                return
            }
            guard preserve else { return }
            let maxY = max(0, contentHeight - visibleHeight)
            let y = min(max(0, origin.y), maxY)
            self.scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: y))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func emptyStateMessage(
        isLoading: Bool,
        workspaceFilter: WorkspaceShellViewController.VaultWorkspaceFilter,
        workspaceFilterItems: [WorkspaceFilterItem],
        selectedAgent: VaultAgentKind?,
        searchQuery: String
    ) -> String {
        if isLoading {
            return "Loading sessions..."
        }
        if selectedAgent != nil || searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return "No sessions match your filters/search"
        }
        switch workspaceFilter {
        case .all:
            return "No sessions across all workspaces"
        case .current:
            return "No sessions for this workspace"
        case .workspace:
            if let title = workspaceFilterItems.first(where: { $0.filter == workspaceFilter })?.title {
                return "No sessions in \(title)"
            }
            return "No sessions for this workspace"
        }
    }

    private static func visibleRows(
        sessions: [VaultSessionSummary],
        sessionActivityByID: [String: SessionActivity]
    ) -> [SessionRowState] {
        sessions
            .map { session in
                SessionRowState(session: session, activity: sessionActivityByID[session.id])
            }
            .sorted { lhs, rhs in
                let lhsActive = lhs.activity?.isActive == true
                let rhsActive = rhs.activity?.isActive == true
                if lhsActive != rhsActive {
                    return lhsActive
                }
                return lhs.session.modifiedAt > rhs.session.modifiedAt
            }
    }

    private func rebuildAgentMenu(availableAgents: Set<VaultAgentKind>, selectedAgent: VaultAgentKind?) {
        let previousAction = agentPopup.action
        agentPopup.action = nil
        agentPopup.removeAllItems()
        agentPopup.addItem(withTitle: "All agents")
        agentPopup.lastItem?.representedObject = Optional<VaultAgentKind>.none as Any
        var agents = VaultAgentKind.allCases.filter { availableAgents.contains($0) }
        if let selectedAgent, agents.contains(selectedAgent) == false {
            agents.append(selectedAgent)
        }
        for agent in agents {
            agentPopup.addItem(withTitle: agent.rawValue)
            agentPopup.lastItem?.representedObject = agent
        }
        if let selectedAgent,
           let item = agentPopup.itemArray.first(where: { ($0.representedObject as? VaultAgentKind) == selectedAgent }) {
            agentPopup.select(item)
        } else {
            agentPopup.selectItem(at: 0)
        }
        agentPopup.action = previousAction
    }

    private func rebuildWorkspaceMenu(
        items: [WorkspaceFilterItem],
        selectedFilter: WorkspaceShellViewController.VaultWorkspaceFilter
    ) {
        let previousAction = workspacePopup.action
        workspacePopup.action = nil
        workspacePopup.removeAllItems()
        for item in items {
            workspacePopup.addItem(withTitle: item.title)
            workspacePopup.lastItem?.representedObject = VaultWorkspaceFilterBox(item.filter)
        }
        if let item = workspacePopup.itemArray.first(where: {
            ($0.representedObject as? VaultWorkspaceFilterBox)?.filter == selectedFilter
        }) {
            workspacePopup.select(item)
        } else {
            workspacePopup.selectItem(at: 0)
        }
        workspacePopup.action = previousAction
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func agentFilterChanged() {
        onAgentFilterChanged?(agentPopup.selectedItem?.representedObject as? VaultAgentKind)
    }

    @objc private func workspaceFilterChanged() {
        guard let filter = (workspacePopup.selectedItem?.representedObject as? VaultWorkspaceFilterBox)?.filter else {
            return
        }
        onWorkspaceFilterChanged?(filter)
    }

    @objc private func scrollBoundsChanged(_ notification: Notification) {
        _ = notification
        let visibleMaxY = scrollView.contentView.bounds.maxY
        let contentHeight = stack.frame.height
        if contentHeight - visibleMaxY < 180 {
            onNeedsMore?()
        }
    }

}

extension WorkspaceVaultSidebarView {
    func controlTextDidBeginEditing(_ obj: Notification) {
        _ = obj
        isSearchFocused = true
        applySearchFieldTheme()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        _ = obj
        isSearchFocused = false
        applySearchFieldTheme()
    }

    func controlTextDidChange(_ obj: Notification) {
        _ = obj
        onSearchChanged?(searchField.stringValue)
    }
}

@MainActor
private final class AgentSessionsSearchField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let centeredCell = AgentSessionsSearchFieldCell()
        centeredCell.isEditable = true
        centeredCell.isSelectable = true
        centeredCell.isBordered = false
        centeredCell.backgroundColor = NSColor.clear
        centeredCell.focusRingType = NSFocusRingType.none
        centeredCell.usesSingleLineMode = true
        centeredCell.lineBreakMode = NSLineBreakMode.byClipping
        cell = centeredCell
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class AgentSessionsSearchFieldCell: NSTextFieldCell {
    private func centeredRect(for rect: NSRect) -> NSRect {
        let size = cellSize(forBounds: rect)
        let y = rect.minY + (rect.height - size.height) / 2
        return NSRect(x: rect.minX, y: y, width: rect.width, height: size.height)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredRect(for: cellFrame), in: controlView)
    }
}

@MainActor
private final class VaultSessionRowButton: NSControl {
    private let session: VaultSessionSummary
    private let activity: WorkspaceVaultSidebarView.SessionActivity?
    private let titleLabel = NSTextField(labelWithString: "")
    private let activeLabel = NSTextField(labelWithString: "ACTIVE")
    private let statusOrb = PaneProgressOrbView()
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let deleteButton = NSButton()
    var onOpen: ((String) -> Void)?
    var onDelete: ((String) -> Void)?

    init(session: VaultSessionSummary, activity: WorkspaceVaultSidebarView.SessionActivity?) {
        self.session = session
        self.activity = activity
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        focusRingType = .exterior
        setAccessibilityRole(.group)
        setAccessibilityLabel(session.title.isEmpty ? session.id : session.title)

        let displayTitle = session.title.isEmpty ? session.id : session.title
        titleLabel.stringValue = displayTitle
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        activeLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        activeLabel.alignment = .right
        activeLabel.maximumNumberOfLines = 1
        activeLabel.translatesAutoresizingMaskIntoConstraints = false
        activeLabel.isHidden = activity?.isActive != true

        statusOrb.translatesAutoresizingMaskIntoConstraints = false
        statusOrb.isHidden = activity == nil

        let folderName = session.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        subtitleLabel.stringValue = "\(session.agent.rawValue) · \(folderName)"
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.stringValue = Self.formattedDate(session.modifiedAt)
        dateLabel.font = .systemFont(ofSize: 10)
        dateLabel.lineBreakMode = .byTruncatingTail
        dateLabel.maximumNumberOfLines = 1
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        let openTitle = activity?.isActive == true ? "Focus Session" : "Open Session"
        let openSymbol = activity?.isActive == true ? "scope" : "arrow.up.right.square"
        openButton.title = ""
        openButton.image = NSImage(systemSymbolName: openSymbol, accessibilityDescription: openTitle)
        openButton.imagePosition = .imageOnly
        openButton.toolTip = openTitle
        openButton.isBordered = false
        openButton.controlSize = .small
        openButton.setButtonType(.momentaryChange)
        openButton.setAccessibilityLabel(openTitle)
        openButton.target = self
        openButton.action = #selector(openSession)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.title = ""
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Session")
        deleteButton.imagePosition = .imageOnly
        deleteButton.isBordered = false
        deleteButton.controlSize = .small
        deleteButton.setButtonType(.momentaryChange)
        deleteButton.setAccessibilityLabel("Delete Session")
        deleteButton.target = self
        deleteButton.action = #selector(deleteSession)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(activeLabel)
        addSubview(statusOrb)
        addSubview(subtitleLabel)
        addSubview(dateLabel)
        addSubview(openButton)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 62),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -8),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),
            openButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 22),
            openButton.heightAnchor.constraint(equalToConstant: 22),
            activeLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -8),
            activeLabel.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
            statusOrb.trailingAnchor.constraint(equalTo: activeLabel.leadingAnchor, constant: -6),
            statusOrb.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),
            statusOrb.widthAnchor.constraint(equalToConstant: PaneProgressOrbView.side),
            statusOrb.heightAnchor.constraint(equalToConstant: PaneProgressOrbView.side),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -8),
            dateLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusOrb.leadingAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = NSColor.clear.cgColor
        titleLabel.textColor = theme.shell.textPrimary
        subtitleLabel.textColor = theme.shell.textMuted
        dateLabel.textColor = theme.shell.textMuted
        activeLabel.textColor = theme.shell.accent
        openButton.contentTintColor = theme.shell.textMuted
        deleteButton.contentTintColor = theme.shell.textMuted
        statusOrb.configure(progress: activity?.progress, theme: theme)
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        _ = event
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            onOpen?(session.id)
        } else if event.keyCode == 51 {
            onDelete?(session.id)
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: activity?.isActive == true ? "Focus Session" : "Open Session", action: #selector(openSession), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let deleteItem = NSMenuItem(title: "Delete Session…", action: #selector(deleteSession), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?(session.id)
        return true
    }

    @objc private func openSession() {
        onOpen?(session.id)
    }

    @objc private func deleteSession() {
        onDelete?(session.id)
    }
}

@MainActor
final class ShellOverlayHostView: NSView {
    private final class PassthroughOverlayView: NSView {
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let hitView = super.hitTest(point)
            return hitView === self ? nil : hitView
        }
    }

    private final class BlockingOverlayView: NSView {
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // When no modal content is shown, pass events through to views
            // below the overlay so terminal interaction (including drag and
            // drop) is not blocked.  When a modal IS shown the subview
            // captures the hit inside its frame; clicks outside the modal
            // still hit self, which keeps them from reaching the terminal.
            guard subviews.isEmpty == false else {
                return nil
            }
            return super.hitTest(point)
        }
    }

    private let paletteHostView = PassthroughOverlayView()
    private let modalHostView = BlockingOverlayView()
    let floatingModalOverlayView = FloatingModalOverlayView()
    private var currentTheme: WorkspaceShellTheme = .defaultTheme

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        paletteHostView.translatesAutoresizingMaskIntoConstraints = false
        modalHostView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(floatingModalOverlayView)
        addSubview(paletteHostView)
        addSubview(modalHostView)

        NSLayoutConstraint.activate([
            floatingModalOverlayView.topAnchor.constraint(equalTo: topAnchor),
            floatingModalOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            floatingModalOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            floatingModalOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            paletteHostView.topAnchor.constraint(equalTo: topAnchor),
            paletteHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            paletteHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            paletteHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            modalHostView.topAnchor.constraint(equalTo: topAnchor),
            modalHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            modalHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            modalHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        floatingModalOverlayView.apply(theme: theme)
        modalHostView.subviews.compactMap { $0 as? AgentSessionPathMismatchModalView }.forEach { $0.apply(theme: theme) }
    }

    func present(commandPaletteView: CommandPaletteView) {
        if commandPaletteView.superview !== paletteHostView {
            paletteHostView.addSubview(commandPaletteView)
            NSLayoutConstraint.activate([
                commandPaletteView.topAnchor.constraint(equalTo: paletteHostView.topAnchor),
                commandPaletteView.leadingAnchor.constraint(equalTo: paletteHostView.leadingAnchor),
                commandPaletteView.trailingAnchor.constraint(equalTo: paletteHostView.trailingAnchor),
                commandPaletteView.bottomAnchor.constraint(equalTo: paletteHostView.bottomAnchor),
            ])
        }
        commandPaletteView.apply(theme: currentTheme)
    }

    func dismiss(commandPaletteView: CommandPaletteView) {
        if commandPaletteView.superview === paletteHostView {
            commandPaletteView.removeFromSuperview()
        }
    }

    func present(agentSessionPathMismatchView modalView: AgentSessionPathMismatchModalView) {
        modalHostView.subviews.forEach { $0.removeFromSuperview() }
        modalView.apply(theme: currentTheme)
        modalHostView.addSubview(modalView)
        let preferredWidth = modalView.widthAnchor.constraint(equalToConstant: 460)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            modalView.centerXAnchor.constraint(equalTo: modalHostView.centerXAnchor),
            modalView.centerYAnchor.constraint(equalTo: modalHostView.centerYAnchor),
            modalView.widthAnchor.constraint(lessThanOrEqualTo: modalHostView.widthAnchor, constant: -48),
            preferredWidth,
        ])
        window?.makeFirstResponder(modalView)
    }

    func dismiss(agentSessionPathMismatchView modalView: AgentSessionPathMismatchModalView) {
        if modalView.superview === modalHostView {
            modalView.removeFromSuperview()
        }
    }
}

@MainActor
enum AgentSessionPathMismatchChoice {
    case resumeHere
    case openWorkspace
    case cancel
}

@MainActor
final class AgentSessionPathMismatchModalView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Session Path Differs")
    private let messageLabel = NSTextField(labelWithString: "")
    private let resumeButton = AgentSessionModalButton(title: "Resume Here", active: true)
    private let openWorkspaceButton = AgentSessionModalButton(title: "Open Workspace", active: false)
    private let cancelButton = AgentSessionModalButton(title: "Cancel", active: false)
    private let workingDirectory: String?
    private let connectedPaths: [String]
    var onChoice: ((AgentSessionPathMismatchChoice) -> Void)?

    init(workingDirectory: String?, connectedPaths: [String], theme: WorkspaceShellTheme) {
        self.workingDirectory = workingDirectory
        self.connectedPaths = connectedPaths
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        setAccessibilityRole(.group)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let sessionPath = workingDirectory ?? "unknown"
        let currentPath = connectedPaths.isEmpty ? "unknown" : connectedPaths.joined(separator: ", ")
        messageLabel.stringValue = "This agent session was captured in:\n\(sessionPath)\n\nCurrent workspace paths:\n\(currentPath)"
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.maximumNumberOfLines = 6
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        resumeButton.onPress = { [weak self] in self?.onChoice?(.resumeHere) }
        openWorkspaceButton.onPress = { [weak self] in self?.onChoice?(.openWorkspace) }
        cancelButton.onPress = { [weak self] in self?.onChoice?(.cancel) }
        openWorkspaceButton.isEnabled = workingDirectory != nil

        let buttonRow = NSStackView(views: [cancelButton, NSView(), openWorkspaceButton, resumeButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(buttonRow)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonRow.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 18),
            buttonRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        apply(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onChoice?(.cancel)
        } else if event.keyCode == 36 {
            onChoice?(.resumeHere)
        } else {
            super.keyDown(with: event)
        }
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.paneCardBackground.cgColor
        layer?.borderColor = theme.shell.subduedBorder.cgColor
        titleLabel.textColor = theme.shell.textPrimary
        messageLabel.textColor = theme.shell.textSecondary
        resumeButton.apply(theme: theme)
        openWorkspaceButton.apply(theme: theme)
        cancelButton.apply(theme: theme)
    }
}

@MainActor
private final class AgentSessionModalButton: NSControl {
    var onPress: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let title: String
    private let active: Bool
    private var theme = WorkspaceShellTheme.defaultTheme

    init(title: String, active: Bool) {
        self.title = title
        self.active = active
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: active ? .semibold : .medium)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(theme: WorkspaceShellTheme) {
        self.theme = theme
        titleLabel.textColor = active ? theme.shell.selectedText : theme.shell.textSecondary
        layer?.backgroundColor = (active ? theme.shell.selection : theme.shell.chromeButtonBackground).cgColor
        layer?.borderWidth = active ? 0 : 1
        layer?.borderColor = theme.shell.subduedBorder.cgColor
        alphaValue = isEnabled ? 1 : 0.45
    }

    override var isEnabled: Bool {
        didSet { apply(theme: theme) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onPress?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            onPress?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class FloatingModalOverlayView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var currentTheme: WorkspaceShellTheme = .defaultTheme

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        currentTheme = theme
        subviews.compactMap { $0 as? FloatingPaneModalView }.forEach { $0.apply(theme: theme) }
    }

    func render(modalViews: [FloatingPaneModalView]) {
        subviews.forEach { $0.removeFromSuperview() }
        for modalView in modalViews {
            modalView.apply(theme: currentTheme)
            addSubview(modalView)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

@MainActor
final class FloatingPaneModalHeaderView: NSView {
    var onMouseDownEvent: ((NSEvent) -> Void)?
    var onMouseDraggedEvent: ((NSEvent) -> Void)?
    var onMouseUpEvent: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onMouseDownEvent?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDraggedEvent?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUpEvent?(event)
    }
}

@MainActor
final class FloatingPaneModalResizeHandleView: NSView {
    var onMouseDownEvent: ((NSEvent) -> Void)?
    var onMouseDraggedEvent: ((NSEvent) -> Void)?
    var onMouseUpEvent: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onMouseDownEvent?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDraggedEvent?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUpEvent?(event)
    }
}

@MainActor
final class FloatingPaneModalView: NSView {
    private static let minimumWidth = CGFloat(360)
    private static let minimumHeight = CGFloat(240)
    private static let resizeHandleSide = CGFloat(18)

    private let modalID: FloatingPaneModalID
    private let paneID: PaneID
    private let sourceStackID: PaneStackID
    private let dragHandleView = FloatingPaneModalHeaderView()
    private let resizeHandleView = FloatingPaneModalResizeHandleView()
    private let resizeHandleGlyph = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = ChromePillButton()
    private let contentHostView = NSView()
    private let onFocus: @MainActor (PaneID) -> Void
    private let onClose: @MainActor (PaneID) -> Void
    private let onDragChanged: @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void
    private let onDragEnded: @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void
    private var dragOrigin: CGPoint?
    private var initialFrameOrigin: CGPoint = .zero
    private var resizeOrigin: CGPoint?
    private var initialFrameSize: CGSize = .zero

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        modalID: FloatingPaneModalID,
        paneID: PaneID,
        sourceStackID: PaneStackID,
        title: String,
        contentView: NSView,
        frameModel: FloatingPaneModalFrame,
        theme: WorkspaceShellTheme,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        onClose: @escaping @MainActor (PaneID) -> Void,
        onDragChanged: @escaping @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void,
        onDragEnded: @escaping @MainActor (PaneID, PaneStackID, FloatingPaneModalID, NSRect, Bool) -> Void
    ) {
        self.modalID = modalID
        self.paneID = paneID
        self.sourceStackID = sourceStackID
        self.onFocus = onFocus
        self.onClose = onClose
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        super.init(frame: NSRect(x: frameModel.x, y: frameModel.y, width: frameModel.width, height: frameModel.height))
        translatesAutoresizingMaskIntoConstraints = true
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: 10)
        layer?.masksToBounds = false

        dragHandleView.translatesAutoresizingMaskIntoConstraints = false
        dragHandleView.wantsLayer = true
        dragHandleView.layer?.cornerRadius = 12
        dragHandleView.onMouseDownEvent = { [weak self] event in
            self?.handleHeaderMouseDown(event)
        }
        dragHandleView.onMouseDraggedEvent = { [weak self] event in
            self?.handleHeaderMouseDragged(event)
        }
        dragHandleView.onMouseUpEvent = { [weak self] event in
            self?.handleHeaderMouseUp(event)
        }

        resizeHandleView.translatesAutoresizingMaskIntoConstraints = false
        resizeHandleView.onMouseDownEvent = { [weak self] event in
            self?.handleResizeMouseDown(event)
        }
        resizeHandleView.onMouseDraggedEvent = { [weak self] event in
            self?.handleResizeMouseDragged(event)
        }
        resizeHandleView.onMouseUpEvent = { [weak self] event in
            self?.handleResizeMouseUp(event)
        }
        resizeHandleView.toolTip = "Resize modal"

        resizeHandleGlyph.translatesAutoresizingMaskIntoConstraints = false
        resizeHandleGlyph.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Resize modal")
        resizeHandleGlyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        resizeHandleGlyph.imageScaling = .scaleProportionallyDown
        resizeHandleView.addSubview(resizeHandleGlyph)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = title

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.configure(
            symbolName: "xmark",
            accessibilityLabel: "Close modal",
            active: false,
            theme: theme,
            compact: true
        )
        closeButton.onPress = { [weak self] in
            self?.handleClose(nil)
        }

        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.wantsLayer = true
        contentView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentHostView)
        addSubview(dragHandleView)
        addSubview(resizeHandleView)
        contentHostView.addSubview(contentView)
        dragHandleView.addSubview(titleLabel)
        dragHandleView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            dragHandleView.topAnchor.constraint(equalTo: topAnchor),
            dragHandleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragHandleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragHandleView.heightAnchor.constraint(equalToConstant: 28),

            closeButton.leadingAnchor.constraint(equalTo: dragHandleView.leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: dragHandleView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: dragHandleView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: dragHandleView.centerYAnchor),

            contentHostView.topAnchor.constraint(equalTo: dragHandleView.bottomAnchor, constant: 4),
            contentHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),

            resizeHandleView.widthAnchor.constraint(equalToConstant: Self.resizeHandleSide),
            resizeHandleView.heightAnchor.constraint(equalToConstant: Self.resizeHandleSide),
            resizeHandleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            resizeHandleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            resizeHandleGlyph.centerXAnchor.constraint(equalTo: resizeHandleView.centerXAnchor),
            resizeHandleGlyph.centerYAnchor.constraint(equalTo: resizeHandleView.centerYAnchor),
        ])

        apply(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.shell.paneHeaderBackground.cgColor
        contentHostView.layer?.cornerRadius = 12
        contentHostView.layer?.masksToBounds = true
        contentHostView.layer?.backgroundColor = theme.shell.canvasBackground.cgColor
        dragHandleView.layer?.backgroundColor = theme.shell.paneHeaderBackground.cgColor
        titleLabel.textColor = theme.shell.textPrimary
        closeButton.applyTheme(theme)
        resizeHandleGlyph.contentTintColor = theme.shell.textMuted
    }

    private func handleHeaderMouseDown(_ event: NSEvent) {
        guard let superview else {
            return
        }
        onFocus(paneID)
        dragOrigin = superview.convert(event.locationInWindow, from: nil)
        initialFrameOrigin = frame.origin
    }

    private func handleHeaderMouseDragged(_ event: NSEvent) {
        guard let superview, let dragOrigin else {
            return
        }
        let location = superview.convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: location.x - dragOrigin.x, y: location.y - dragOrigin.y)
        frame.origin = CGPoint(
            x: max(0, min(initialFrameOrigin.x + delta.x, superview.bounds.width - frame.width)),
            y: max(0, min(initialFrameOrigin.y + delta.y, superview.bounds.height - frame.height))
        )
        onDragChanged(paneID, sourceStackID, modalID, frame, event.modifierFlags.contains(.command) == false)
    }

    private func handleHeaderMouseUp(_ event: NSEvent) {
        guard dragOrigin != nil else {
            return
        }
        dragOrigin = nil
        onDragEnded(paneID, sourceStackID, modalID, frame, event.modifierFlags.contains(.command) == false)
    }

    private func handleResizeMouseDown(_ event: NSEvent) {
        guard let superview else {
            return
        }
        onFocus(paneID)
        resizeOrigin = superview.convert(event.locationInWindow, from: nil)
        initialFrameSize = frame.size
        initialFrameOrigin = frame.origin
    }

    private func handleResizeMouseDragged(_ event: NSEvent) {
        guard let superview, let resizeOrigin else {
            return
        }
        let location = superview.convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: location.x - resizeOrigin.x, y: location.y - resizeOrigin.y)
        frame.size = CGSize(
            width: max(Self.minimumWidth, min(initialFrameSize.width + delta.x, superview.bounds.width - initialFrameOrigin.x)),
            height: max(Self.minimumHeight, min(initialFrameSize.height + delta.y, superview.bounds.height - initialFrameOrigin.y))
        )
        onDragChanged(paneID, sourceStackID, modalID, frame, false)
    }

    private func handleResizeMouseUp(_ event: NSEvent) {
        guard resizeOrigin != nil else {
            return
        }
        resizeOrigin = nil
        onDragEnded(paneID, sourceStackID, modalID, frame, false)
    }

    @objc private func handleClose(_ sender: Any?) {
        onClose(paneID)
    }
}

@MainActor
final class WorkspaceCanvasView: NSView {
    private var currentContentView: NSView?
    private var rootSplitPreview: PaneSplitPreviewView?

    var currentLayoutView: NSView? {
        currentContentView
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
    }

    func render(layoutView: NSView?, theme: WorkspaceShellTheme) {
        apply(theme: theme)
        currentContentView?.removeFromSuperview()
        currentContentView = nil

        guard let layoutView else {
            return
        }

        layoutView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layoutView)
        currentContentView = layoutView
        NSLayoutConstraint.activate([
            layoutView.topAnchor.constraint(equalTo: topAnchor, constant: ShellLayoutMetrics.canvasPadding),
            layoutView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ShellLayoutMetrics.canvasPadding),
            layoutView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ShellLayoutMetrics.canvasPadding),
            layoutView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ShellLayoutMetrics.canvasPadding),
        ])
    }

    func setRootSplitPreview(_ direction: PaneSplitDropDirection, theme: WorkspaceShellTheme) {
        if rootSplitPreview == nil {
            let preview = PaneSplitPreviewView()
            addSubview(preview, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
            rootSplitPreview = preview
        }
        rootSplitPreview?.update(direction: direction, theme: theme, in: bounds)
    }

    func clearRootSplitPreview() {
        rootSplitPreview?.removeFromSuperview()
        rootSplitPreview = nil
    }
}

@MainActor
final class SplitLayoutView: NSView {
    private struct DragState {
        let dividerIndex: Int
        let initialLocation: CGFloat
        let initialLengths: [CGFloat]
    }

    private let axis: PaneSplitAxis
    private var childPaneIDs: [PaneID]
    private let onResize: ([PaneID], [Double]) -> Void
    private var desiredProportions: [Double]
    private var dividerRects: [NSRect] = []
    private var dividerHitRects: [NSRect] = []
    private var dragState: DragState?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        axis: PaneSplitAxis,
        proportions: [Double],
        childPaneIDs: [PaneID],
        onResize: @escaping ([PaneID], [Double]) -> Void
    ) {
        self.axis = axis
        self.childPaneIDs = childPaneIDs
        self.onResize = onResize
        self.desiredProportions = Self.normalizedProportions(proportions, count: childPaneIDs.count)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        applyLayout()
    }

    var childLayoutViews: [NSView] {
        subviews
    }

    func canReconcile(axis: PaneSplitAxis, childCount: Int) -> Bool {
        self.axis == axis && subviews.count == childCount
    }

    func updateLayout(proportions: [Double], childPaneIDs: [PaneID]) {
        self.childPaneIDs = childPaneIDs
        desiredProportions = Self.normalizedProportions(proportions, count: childPaneIDs.count)
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.35).setFill()
        for rect in dividerRects where dirtyRect.intersects(rect) {
            rect.fill()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor = axis == .columns ? .resizeLeftRight : .resizeUpDown
        dividerHitRects.forEach { addCursorRect($0, cursor: cursor) }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let dividerIndex = dividerHitRects.firstIndex(where: { $0.contains(location) }) else {
            return
        }

        dragState = DragState(
            dividerIndex: dividerIndex,
            initialLocation: primaryCoordinate(of: location),
            initialLengths: currentLengths()
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragState else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let delta = primaryCoordinate(of: location) - dragState.initialLocation
        let leadingIndex = dragState.dividerIndex
        let trailingIndex = leadingIndex + 1
        guard dragState.initialLengths.indices.contains(leadingIndex),
              dragState.initialLengths.indices.contains(trailingIndex)
        else {
            return
        }

        let minimumLeading = minimumPrimaryExtent(ofSubviewAt: leadingIndex)
        let minimumTrailing = minimumPrimaryExtent(ofSubviewAt: trailingIndex)
        let minimumDelta = minimumLeading - dragState.initialLengths[leadingIndex]
        let maximumDelta = dragState.initialLengths[trailingIndex] - minimumTrailing
        let clampedDelta = min(max(delta, minimumDelta), maximumDelta)

        var updatedLengths = dragState.initialLengths
        updatedLengths[leadingIndex] += clampedDelta
        updatedLengths[trailingIndex] -= clampedDelta

        desiredProportions = normalizedProportions(for: updatedLengths)
        needsLayout = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragState != nil else {
            return
        }

        dragState = nil
        guard childPaneIDs.count == subviews.count, subviews.count > 1 else {
            return
        }
        onResize(childPaneIDs, desiredProportions)
    }

    private func applyLayout() {
        guard subviews.isEmpty == false else {
            dividerRects = []
            dividerHitRects = []
            return
        }

        let spacing = ShellLayoutMetrics.splitSpacing
        let hitArea = ShellLayoutMetrics.splitHitArea
        let hitPad = (hitArea - spacing) / 2
        let availableLength = max(primaryLength(of: bounds.size) - spacing * CGFloat(max(subviews.count - 1, 0)), 0)
        let lengths = resolvedLengths(totalLength: availableLength)

        var cursor: CGFloat = 0
        dividerRects = []
        dividerHitRects = []

        for (index, subview) in subviews.enumerated() {
            let length = lengths[index]
            let frame: NSRect
            if axis == .columns {
                frame = NSRect(x: cursor, y: 0, width: length, height: bounds.height)
            } else {
                frame = NSRect(x: 0, y: cursor, width: bounds.width, height: length)
            }
            subview.frame = frame
            cursor += length

            if index < subviews.count - 1 {
                let dividerRect: NSRect
                let hitRect: NSRect
                if axis == .columns {
                    dividerRect = NSRect(x: cursor, y: 0, width: spacing, height: bounds.height)
                    hitRect = NSRect(x: cursor - hitPad, y: 0, width: hitArea, height: bounds.height)
                } else {
                    dividerRect = NSRect(x: 0, y: cursor, width: bounds.width, height: spacing)
                    hitRect = NSRect(x: 0, y: cursor - hitPad, width: bounds.width, height: hitArea)
                }
                dividerRects.append(dividerRect)
                dividerHitRects.append(hitRect)
                cursor += spacing
            }
        }

        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func currentLengths() -> [CGFloat] {
        subviews.map { primaryLength(of: $0.frame.size) }
    }

    private func resolvedLengths(totalLength: CGFloat) -> [CGFloat] {
        guard subviews.isEmpty == false else {
            return []
        }

        if totalLength <= 0 {
            return Array(repeating: 0, count: subviews.count)
        }

        let minimums = subviews.indices.map(minimumPrimaryExtent(ofSubviewAt:))
        let minimumTotal = minimums.reduce(0, +)
        guard minimumTotal < totalLength else {
            return Array(repeating: totalLength / CGFloat(subviews.count), count: subviews.count)
        }

        let normalized = Self.normalizedProportions(desiredProportions, count: subviews.count)
        var lengths = normalized.map { CGFloat($0) * totalLength }
        var remainingIndices = Set(lengths.indices)
        var remainingLength = totalLength

        while true {
            let undersized = remainingIndices.filter { lengths[$0] < minimums[$0] }
            guard undersized.isEmpty == false else {
                break
            }

            for index in undersized {
                lengths[index] = minimums[index]
                remainingIndices.remove(index)
                remainingLength -= minimums[index]
            }

            guard remainingIndices.isEmpty == false else {
                break
            }

            let remainingWeight = remainingIndices.reduce(CGFloat(0)) { partialResult, index in
                partialResult + CGFloat(normalized[index])
            }

            for index in remainingIndices {
                let weight = remainingWeight > 0 ? CGFloat(normalized[index]) / remainingWeight : 1 / CGFloat(remainingIndices.count)
                lengths[index] = remainingLength * weight
            }
        }

        let correction = totalLength - lengths.reduce(0, +)
        if let lastIndex = lengths.indices.last {
            lengths[lastIndex] += correction
        }

        return lengths
    }

    private func minimumPrimaryExtent(ofSubviewAt index: Int) -> CGFloat {
        guard subviews.indices.contains(index) else {
            return 0
        }

        let fittingSize = subviews[index].fittingSize
        return max(primaryLength(of: fittingSize), 120)
    }

    private func primaryLength(of size: CGSize) -> CGFloat {
        axis == .columns ? size.width : size.height
    }

    private func primaryCoordinate(of point: CGPoint) -> CGFloat {
        axis == .columns ? point.x : point.y
    }

    private func normalizedProportions(for lengths: [CGFloat]) -> [Double] {
        let total = lengths.reduce(0, +)
        guard total > 0 else {
            return Self.normalizedProportions([], count: lengths.count)
        }
        return lengths.map { Double($0 / total) }
    }

    private static func normalizedProportions(_ proportions: [Double], count: Int) -> [Double] {
        guard count > 0 else {
            return []
        }

        guard proportions.count == count,
              proportions.allSatisfy({ $0.isFinite && $0 > 0 })
        else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }

        let total = proportions.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }
        return proportions.map { $0 / total }
    }
}

@MainActor
private protocol WorkspacePaneRendering: AnyObject {
    var rootPaneView: NSView { get }
    var focusTarget: NSView { get }
    var representedPaneID: PaneID { get }
    func updateFocusState(_ isFocused: Bool)
    func apply(theme: WorkspaceShellTheme)
}

extension HostedTerminalPaneView: WorkspacePaneRendering {
    fileprivate var rootPaneView: NSView { self }

    fileprivate func apply(theme: WorkspaceShellTheme) {
        apply(themePalette: theme.terminalPalette)
    }
}

@MainActor
private final class ExtensionPaneHostView: NSView, WorkspacePaneRendering, WKNavigationDelegate, WKScriptMessageHandler {
    private struct ScrollPosition {
        let x: Double
        let y: Double
    }

    private static var scrollPositionBySource: [String: ScrollPosition] = [:]
    private let paneID: PaneID
    private var descriptor: ExtensionPaneDescriptor
    private var scrollStateSource: String
    private let onFocus: @MainActor (PaneID) -> Void
    private let onAction: @MainActor (ExtensionPaneActionRequest) -> Void
    private let container = NSView()
    private let placeholderLabel = NSTextField(wrappingLabelWithString: "")
    private let webView: WKWebView
    private var isLoadingInjectedHTML = false
    private var pendingScrollPosition: ScrollPosition?
    private var lastRenderedHTML: String?

    init(
        pane: Pane,
        descriptor: ExtensionPaneDescriptor,
        isFocused: Bool,
        theme: WorkspaceShellTheme,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        onAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void
    ) {
        self.paneID = pane.id
        self.descriptor = descriptor
        self.scrollStateSource = descriptor.source ?? pane.id.rawValue
        self.onFocus = onFocus
        self.onAction = onAction

        let configuration = WKWebViewConfiguration()
        let allowsContentJavaScript = descriptor.actionsEnabled || descriptor.pluginID == "dev.fingergun.markdown-preview"
        configuration.defaultWebpagePreferences.allowsContentJavaScript = allowsContentJavaScript
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.scrollStateBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        if descriptor.actionsEnabled {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.bridgeScript(paneID: pane.id, pluginID: descriptor.pluginID),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        addSubview(container)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: "omuxScrollState"
        )
        if descriptor.actionsEnabled {
            webView.configuration.userContentController.add(
                WeakScriptMessageHandler(delegate: self),
                name: "omuxAction"
            )
        }
        container.addSubview(webView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alignment = .center
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.maximumNumberOfLines = 0
        container.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 280),

            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            placeholderLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])

        apply(theme: theme)
        updateFocusState(isFocused)
        renderContent(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var rootPaneView: NSView { self }
    var focusTarget: NSView { webView }
    var representedPaneID: PaneID { paneID }

    override func mouseDown(with event: NSEvent) {
        onFocus(paneID)
        window?.makeFirstResponder(focusTarget)
        super.mouseDown(with: event)
    }

    func updateFocusState(_ isFocused: Bool) {
        layer?.borderWidth = 0
    }

    func update(
        pane: Pane,
        descriptor: ExtensionPaneDescriptor,
        isFocused: Bool,
        theme: WorkspaceShellTheme
    ) {
        self.descriptor = descriptor
        self.scrollStateSource = descriptor.source ?? pane.id.rawValue
        apply(theme: theme)
        updateFocusState(isFocused)
        renderContent(theme: theme)
    }

    func apply(theme: WorkspaceShellTheme) {
        layer?.backgroundColor = theme.terminalPalette.backgroundColor.cgColor
        container.layer?.backgroundColor = theme.terminalPalette.backgroundColor.cgColor
        placeholderLabel.textColor = theme.shell.textSecondary
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if isLoadingInjectedHTML, navigationAction.navigationType == .other {
            isLoadingInjectedHTML = false
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoadingInjectedHTML = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoadingInjectedHTML = false
        restorePendingScrollPosition()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoadingInjectedHTML = false
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "omuxScrollState",
           let position = Self.scrollPosition(from: message.body) {
            Self.scrollPositionBySource[scrollStateSource] = position
            return
        }

        guard message.name == "omuxAction",
              let actionRequest = Self.actionRequest(
                from: message.body,
                expectedPaneID: paneID,
                expectedPluginID: descriptor.pluginID
              )
        else {
            return
        }
        onAction(actionRequest)
    }

    private func renderContent(theme: WorkspaceShellTheme) {
        guard descriptor.status == .ready,
              descriptor.contentKind == .html,
              let html = descriptor.html,
              html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            webView.isHidden = true
            placeholderLabel.isHidden = false
            placeholderLabel.stringValue = placeholderMessage
            lastRenderedHTML = nil
            return
        }

        placeholderLabel.isHidden = true
        webView.isHidden = false
        if lastRenderedHTML == html {
            return
        }
        pendingScrollPosition = Self.scrollPositionBySource[scrollStateSource]
        isLoadingInjectedHTML = true
        lastRenderedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func restorePendingScrollPosition() {
        guard let pendingScrollPosition else {
            return
        }
        self.pendingScrollPosition = nil
        webView.evaluateJavaScript(
            "window.scrollTo(\(pendingScrollPosition.x), \(pendingScrollPosition.y));",
            completionHandler: nil
        )
    }

    private var placeholderMessage: String {
        if let message = descriptor.message?.trimmingCharacters(in: .whitespacesAndNewlines), message.isEmpty == false {
            return message
        }

        switch descriptor.status {
        case .ready:
            return "Waiting for \(descriptor.pluginID) content."
        case .disabled:
            return "\(descriptor.pluginID) is disabled."
        case .error:
            return "\(descriptor.pluginID) could not render this pane."
        }
    }

    private var baseURL: URL? {
        descriptor.source.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
    }

    private static func bridgeScript(paneID: PaneID, pluginID: String) -> String {
        let paneJSONString = javascriptString(paneID.rawValue)
        let pluginJSONString = javascriptString(pluginID)
        return """
        (() => {
          const paneID = \(paneJSONString);
          const pluginID = \(pluginJSONString);
          window.omux = Object.freeze({
            submitAction(action, payload = {}) {
              window.webkit.messageHandlers.omuxAction.postMessage({ paneID, pluginID, action, payload });
            }
          });
        })();
        """
    }

    private static var scrollStateBridgeScript: String {
        """
        (() => {
          const post = () => {
            try {
              window.webkit.messageHandlers.omuxScrollState.postMessage({
                x: window.scrollX || 0,
                y: window.scrollY || 0
              });
            } catch (_) {}
          };
          window.addEventListener('scroll', post, { passive: true });
          window.addEventListener('beforeunload', post);
          window.addEventListener('pagehide', post);
          window.addEventListener('load', post);
        })();
        """
    }

    private static func javascriptString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return string
    }

    private static func actionRequest(
        from body: Any,
        expectedPaneID: PaneID,
        expectedPluginID: String
    ) -> ExtensionPaneActionRequest? {
        guard let object = body as? [String: Any],
              let paneID = object["paneID"] as? String,
              let pluginID = object["pluginID"] as? String,
              let action = object["action"] as? String,
              paneID == expectedPaneID.rawValue,
              pluginID == expectedPluginID,
              let payload = omuxValue(from: object["payload"] ?? [:])
        else {
            return nil
        }
        return ExtensionPaneActionRequest(
            paneID: expectedPaneID,
            pluginID: expectedPluginID,
            action: action,
            payload: payload
        )
    }

    private static func scrollPosition(from body: Any) -> ScrollPosition? {
        guard let object = body as? [String: Any] else {
            return nil
        }

        let x: Double
        if let value = object["x"] as? Double {
            x = value
        } else if let value = object["x"] as? Int {
            x = Double(value)
        } else {
            return nil
        }

        let y: Double
        if let value = object["y"] as? Double {
            y = value
        } else if let value = object["y"] as? Int {
            y = Double(value)
        } else {
            return nil
        }

        return ScrollPosition(x: x, y: y)
    }


    private static func omuxValue(from value: Any) -> OmuxValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .integer(int)
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .double(number.doubleValue)
        case let array as [Any]:
            var result: [OmuxValue] = []
            for item in array {
                guard let converted = omuxValue(from: item) else {
                    return nil
                }
                result.append(converted)
            }
            return .array(result)
        case let object as [String: Any]:
            var result: [String: OmuxValue] = [:]
            for (key, nestedValue) in object {
                guard let converted = omuxValue(from: nestedValue) else {
                    return nil
                }
                result[key] = converted
            }
            return .object(result)
        case _ as NSNull:
            return .null
        default:
            return nil
        }
    }
}

@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: (any WKScriptMessageHandler)?

    init(delegate: any WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class PaneStackView: NSView {
    private var paneContentView: NSView
    private var paneRenderer: any WorkspacePaneRendering
    private let paneCardView = PaneCardView()
    private var headerView: PaneHeaderView?
    private var splitPreviewView: PaneSplitPreviewView?
    private var mergePreviewView: PaneMergePreviewView?
    private let showsHeader: Bool

    var paneStackID: PaneStackID?

    init(
        paneStack: PaneStack,
        focusedPaneID: PaneID,
        windowIsKey: Bool,
        inactiveOpacity: Double,
        bridge: GhosttyTerminalBridge,
        theme: WorkspaceShellTheme,
        iconResolver: WorkspaceIconResolver,
        iconConfiguration: OmuxConfigUI.Icons,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        canCloseSinglePaneStack: Bool,
        onClosePane: @escaping @MainActor (PaneID) throws -> Void,
        contextMenuProvider: @escaping @MainActor (Pane) -> NSMenu,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        canStartPaneTabDrag: @escaping @MainActor (PaneID) -> Bool,
        onPaneTabDragStarted: ((NSView, PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragMoved: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragEnded: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragCancelled: (() -> Void)? = nil,
        onTextActivation: @escaping @MainActor (TerminalTextActivationRequest) -> Bool,
        onTextActivationHover: @escaping @MainActor (TerminalTextActivationRequest) -> Bool,
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void,
        onRenamePaneTab: ((PaneID, String) -> Void)? = nil,
        onClearPaneTabAlias: ((PaneID) -> Void)? = nil,
        showsHeader: Bool = true
    ) {
        self.showsHeader = showsHeader
        let activePane = paneStack.focusedPane ?? paneStack.panes[0]
        if let descriptor = activePane.extensionPane {
            let extensionPaneView = ExtensionPaneHostView(
                pane: activePane,
                descriptor: descriptor,
                isFocused: activePane.id == focusedPaneID,
                theme: theme,
                onFocus: onFocus,
                onAction: onExtensionPaneAction
            )
            self.paneRenderer = extensionPaneView
            self.paneContentView = extensionPaneView
        } else {
            let terminalPaneView = bridge.makeHostedPaneView(
                for: activePane,
                isFocused: activePane.id == focusedPaneID,
                themePalette: theme.terminalPalette,
                onFocus: onFocus,
                onTextActivation: onTextActivation,
                onTextActivationHover: onTextActivationHover
            )
            self.paneRenderer = terminalPaneView
            self.paneContentView = terminalPaneView
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.paneStackID = paneStack.id

        let headerView = showsHeader ? PaneHeaderView(
            paneStack: paneStack,
            theme: theme,
            iconResolver: iconResolver,
            iconConfiguration: iconConfiguration,
            terminalTextProvider: terminalTextProvider,
            onSelectPaneTab: onSelectPaneTab,
            onCreatePaneTab: onCreatePaneTab,
            canCloseSinglePaneStack: canCloseSinglePaneStack,
            onClosePane: onClosePane,
            contextMenuProvider: contextMenuProvider,
            canStartPaneTabDrag: canStartPaneTabDrag,
            onPaneTabDragStarted: onPaneTabDragStarted,
            onPaneTabDragMoved: onPaneTabDragMoved,
            onPaneTabDragEnded: onPaneTabDragEnded,
            onPaneTabDragCancelled: onPaneTabDragCancelled,
            onRenamePaneTab: onRenamePaneTab,
            onClearPaneTabAlias: onClearPaneTabAlias
        ) : nil
        self.headerView = headerView
        headerView?.scrollActiveTabToVisible()
        paneCardView.configure(
            headerView: headerView,
            statusText: activePane.terminalState.statusSummary,
            paneRenderer: paneRenderer,
            theme: theme,
            focused: activePane.id == focusedPaneID,
            windowIsKey: windowIsKey,
            inactiveOpacity: inactiveOpacity
        )
        addSubview(paneCardView)

        NSLayoutConstraint.activate([
            paneCardView.topAnchor.constraint(equalTo: topAnchor),
            paneCardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            paneCardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            paneCardView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var focusedPaneView: NSView {
        paneContentView
    }

    func update(
        paneStack: PaneStack,
        focusedPaneID: PaneID,
        windowIsKey: Bool,
        inactiveOpacity: Double,
        bridge: GhosttyTerminalBridge,
        theme: WorkspaceShellTheme,
        iconResolver: WorkspaceIconResolver,
        iconConfiguration: OmuxConfigUI.Icons,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        canCloseSinglePaneStack: Bool,
        onClosePane: @escaping @MainActor (PaneID) throws -> Void,
        contextMenuProvider: @escaping @MainActor (Pane) -> NSMenu,
        onFocus: @escaping @MainActor (PaneID) -> Void,
        canStartPaneTabDrag: @escaping @MainActor (PaneID) -> Bool,
        onPaneTabDragStarted: ((NSView, PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragMoved: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragEnded: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragCancelled: (() -> Void)? = nil,
        onTextActivation: @escaping @MainActor (TerminalTextActivationRequest) -> Bool,
        onTextActivationHover: @escaping @MainActor (TerminalTextActivationRequest) -> Bool,
        onExtensionPaneAction: @escaping @MainActor (ExtensionPaneActionRequest) -> Void,
        onRenamePaneTab: ((PaneID, String) -> Void)? = nil,
        onClearPaneTabAlias: ((PaneID) -> Void)? = nil,
        showsHeader: Bool = true
    ) {
        precondition(showsHeader == self.showsHeader, "PaneStackView header visibility cannot change during reconciliation.")
        self.paneStackID = paneStack.id
        let activePane = paneStack.focusedPane ?? paneStack.panes[0]

        if paneRenderer.representedPaneID != activePane.id {
            if let descriptor = activePane.extensionPane {
                let extensionPaneView = ExtensionPaneHostView(
                    pane: activePane,
                    descriptor: descriptor,
                    isFocused: activePane.id == focusedPaneID,
                    theme: theme,
                    onFocus: onFocus,
                    onAction: onExtensionPaneAction
                )
                paneRenderer = extensionPaneView
                paneContentView = extensionPaneView
            } else {
                let terminalPaneView = bridge.makeHostedPaneView(
                    for: activePane,
                    isFocused: activePane.id == focusedPaneID,
                    themePalette: theme.terminalPalette,
                    onFocus: onFocus,
                    onTextActivation: onTextActivation,
                    onTextActivationHover: onTextActivationHover
                )
                paneRenderer = terminalPaneView
                paneContentView = terminalPaneView
            }
        } else if let descriptor = activePane.extensionPane,
                  let extensionPaneView = paneRenderer as? ExtensionPaneHostView {
            extensionPaneView.update(
                pane: activePane,
                descriptor: descriptor,
                isFocused: activePane.id == focusedPaneID,
                theme: theme
            )
        }

        let headerView = showsHeader ? PaneHeaderView(
            paneStack: paneStack,
            theme: theme,
            iconResolver: iconResolver,
            iconConfiguration: iconConfiguration,
            terminalTextProvider: terminalTextProvider,
            onSelectPaneTab: onSelectPaneTab,
            onCreatePaneTab: onCreatePaneTab,
            canCloseSinglePaneStack: canCloseSinglePaneStack,
            onClosePane: onClosePane,
            contextMenuProvider: contextMenuProvider,
            canStartPaneTabDrag: canStartPaneTabDrag,
            onPaneTabDragStarted: onPaneTabDragStarted,
            onPaneTabDragMoved: onPaneTabDragMoved,
            onPaneTabDragEnded: onPaneTabDragEnded,
            onPaneTabDragCancelled: onPaneTabDragCancelled,
            onRenamePaneTab: onRenamePaneTab,
            onClearPaneTabAlias: onClearPaneTabAlias
        ) : nil
        self.headerView = headerView
        headerView?.scrollActiveTabToVisible()
        paneRenderer.updateFocusState(activePane.id == focusedPaneID)
        paneCardView.configure(
            headerView: headerView,
            statusText: activePane.terminalState.statusSummary,
            paneRenderer: paneRenderer,
            theme: theme,
            focused: activePane.id == focusedPaneID,
            windowIsKey: windowIsKey,
            inactiveOpacity: inactiveOpacity
        )
    }

    func setSplitPreview(_ direction: PaneSplitDropDirection, theme: WorkspaceShellTheme) {
        clearMergePreview()
        if splitPreviewView == nil {
            let preview = PaneSplitPreviewView()
            addSubview(preview, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
            splitPreviewView = preview
        }
        splitPreviewView?.update(direction: direction, theme: theme, in: bounds)
    }

    func setMergePreview(theme: WorkspaceShellTheme) {
        clearSplitPreview()
        if mergePreviewView == nil {
            let preview = PaneMergePreviewView()
            addSubview(preview, positioned: NSWindow.OrderingMode.above, relativeTo: nil)
            mergePreviewView = preview
        }
        mergePreviewView?.update(theme: theme, headerHeight: ShellLayoutMetrics.paneHeaderHeight, in: bounds)
    }

    func clearSplitPreview() {
        splitPreviewView?.removeFromSuperview()
        splitPreviewView = nil
    }

    func clearMergePreview() {
        mergePreviewView?.removeFromSuperview()
        mergePreviewView = nil
    }

    func isWindowPointInHeader(_ windowPoint: NSPoint) -> Bool {
        guard showsHeader else { return false }
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else { return false }
        let threshold = ShellLayoutMetrics.paneHeaderHeight + 4
        return isFlipped ? localPoint.y <= threshold : localPoint.y >= bounds.height - threshold
    }

    func paneTabInsertionIndex(forWindowPoint windowPoint: NSPoint) -> Int? {
        headerView?.insertionIndex(forWindowPoint: windowPoint)
    }
}

@MainActor
private final class PaneSplitPreviewView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(direction: PaneSplitDropDirection, theme: WorkspaceShellTheme, in bounds: NSRect) {
        let half: CGFloat
        let region: NSRect
        switch direction {
        case .left:
            half = bounds.width / 2
            region = NSRect(x: bounds.minX, y: bounds.minY, width: half, height: bounds.height)
        case .right:
            half = bounds.width / 2
            region = NSRect(x: bounds.minX + half, y: bounds.minY, width: half, height: bounds.height)
        case .up:
            half = bounds.height / 2
            region = NSRect(x: bounds.minX, y: bounds.minY + half, width: bounds.width, height: half)
        case .down:
            half = bounds.height / 2
            region = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: half)
        }
        frame = region
        layer?.backgroundColor = theme.shell.selection.withAlphaComponent(0.35).cgColor
        layer?.borderColor = theme.shell.selection.withAlphaComponent(0.8).cgColor
        layer?.borderWidth = 1.5
    }
}

@MainActor
private final class PaneMergePreviewView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(theme: WorkspaceShellTheme, headerHeight: CGFloat, in bounds: NSRect) {
        let region: NSRect
        if isFlipped {
            region = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headerHeight)
        } else {
            region = NSRect(x: bounds.minX, y: bounds.maxY - headerHeight, width: bounds.width, height: headerHeight)
        }
        frame = region
        layer?.backgroundColor = theme.shell.selection.withAlphaComponent(0.45).cgColor
        layer?.borderColor = theme.shell.selection.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 1.5
    }
}

@MainActor
final class PaneCardView: NSView {
    private let container = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        container.orientation = .vertical
        container.alignment = .width
        container.distribution = .fill
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.lineBreakMode = .byTruncatingMiddle

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    fileprivate func configure(
        headerView: PaneHeaderView?,
        statusText: String?,
        paneRenderer: any WorkspacePaneRendering,
        theme: WorkspaceShellTheme,
        focused: Bool,
        windowIsKey: Bool,
        inactiveOpacity: Double
    ) {
        container.arrangedSubviews.forEach { view in
            container.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        paneRenderer.apply(theme: theme)
        let paneView = paneRenderer.rootPaneView
        paneView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        paneView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerView?.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.paneHeaderHeight).isActive = true
        statusLabel.stringValue = statusText ?? ""
        statusLabel.textColor = theme.shell.textMuted
        statusLabel.isHidden = statusText == nil

        if let headerView {
            container.addArrangedSubview(headerView)
            headerView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        }
        if statusText != nil {
            container.addArrangedSubview(statusLabel)
            statusLabel.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
        container.addArrangedSubview(paneView)
        paneView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        alphaValue = (focused && windowIsKey) ? 1.0 : inactiveOpacity
    }
}

@MainActor
final class PaneHeaderView: NSView {
    private let tabStrip = NSStackView()
    private let tabScrollView = NSScrollView()
    private var paneTabButtons: [PaneTabButton] = []
    private let inlineAddButton = ChromePillButton()
    private let pinnedAddButton = ChromePillButton()
    private var contentTrailingToSuperviewConstraint: NSLayoutConstraint?
    private var contentTrailingToPinnedConstraint: NSLayoutConstraint?
    private static let tabMinWidth: CGFloat = 130
    private static let tabMaxWidth: CGFloat = 200

    init(
        paneStack: PaneStack,
        theme: WorkspaceShellTheme,
        iconResolver: WorkspaceIconResolver,
        iconConfiguration: OmuxConfigUI.Icons,
        terminalTextProvider: @escaping @MainActor (Pane) -> String?,
        onSelectPaneTab: @escaping @MainActor (PaneID) -> Void,
        onCreatePaneTab: @escaping @MainActor () throws -> Void,
        canCloseSinglePaneStack: Bool,
        onClosePane: @escaping @MainActor (PaneID) throws -> Void,
        contextMenuProvider: @escaping @MainActor (Pane) -> NSMenu,
        canStartPaneTabDrag: @escaping @MainActor (PaneID) -> Bool,
        onPaneTabDragStarted: ((NSView, PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragMoved: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragEnded: ((PaneID, PaneStackID, NSEvent) -> Void)? = nil,
        onPaneTabDragCancelled: (() -> Void)? = nil,
        onRenamePaneTab: ((PaneID, String) -> Void)? = nil,
        onClearPaneTabAlias: ((PaneID) -> Void)? = nil
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.shell.topBarBackground.cgColor

        let bottomBorder = CALayer()
        bottomBorder.name = "tabBarBottomBorder"
        bottomBorder.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        bottomBorder.frame = CGRect(x: 0, y: 0, width: 0, height: 1)
        bottomBorder.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(bottomBorder)

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false

        tabStrip.orientation = .horizontal
        tabStrip.alignment = .centerY
        tabStrip.spacing = 0
        tabStrip.distribution = .fill
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.identifier = NSUserInterfaceItemIdentifier("pane-tab-strip-\(paneStack.id.rawValue)")
        tabStrip.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabStrip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for pane in paneStack.panes {
            let button = PaneTabButton(
                pane: pane,
                active: pane.id == paneStack.focusedPaneID,
                theme: theme,
                icon: OmuxIconRenderer(
                    configuration: iconConfiguration,
                    pointSize: 11,
                    weight: pane.id == paneStack.focusedPaneID ? .semibold : .medium
                ).render(iconResolver.icon(for: pane, terminalText: terminalTextProvider(pane))),
                progress: pane.terminalState.progress,
                showsClose: paneStack.panes.count > 1 || canCloseSinglePaneStack,
                onClose: {
                    try? onClosePane(pane.id)
                }
            )
            button.onPress = { onSelectPaneTab(pane.id) }
            button.contextMenuProvider = { contextMenuProvider(pane) }
            if let onRenamePaneTab {
                button.onRename = { newName in onRenamePaneTab(pane.id, newName) }
            }
            if let onClearPaneTabAlias {
                button.onClearAlias = { onClearPaneTabAlias(pane.id) }
            }
            if onPaneTabDragStarted != nil {
                button.canStartDrag = { canStartPaneTabDrag(pane.id) }
                button.onDragStarted = { [weak button] _, event in
                    guard let button else { return }
                    onPaneTabDragStarted?(button, pane.id, paneStack.id, event)
                }
                button.onDragMoved = { _, event in onPaneTabDragMoved?(pane.id, paneStack.id, event) }
                button.onDragEnded = { _, event in onPaneTabDragEnded?(pane.id, paneStack.id, event) }
                button.onDragCancelled = { _ in onPaneTabDragCancelled?() }
            }
            tabStrip.addArrangedSubview(button)
            paneTabButtons.append(button)
        }

        // Keep tab visuals balanced like 08efd4d while preserving a usable
        // minimum hit target once multiple tabs are open.
        let tabWidthConstraints: [NSLayoutConstraint] = {
            guard !paneTabButtons.isEmpty else { return [] }
            let first = paneTabButtons[0]
            let count = CGFloat(paneTabButtons.count)
            let shouldEnforceMinWidth = paneTabButtons.count > 1
            var constraints: [NSLayoutConstraint] = []
            for button in paneTabButtons {
                let equalShare = button.widthAnchor.constraint(
                    equalTo: tabScrollView.widthAnchor,
                    multiplier: 1.0 / count
                )
                equalShare.priority = .defaultHigh
                let maxWidth = button.widthAnchor.constraint(lessThanOrEqualToConstant: Self.tabMaxWidth)
                constraints.append(contentsOf: [equalShare, maxWidth])
                if shouldEnforceMinWidth {
                    let minWidth = button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.tabMinWidth)
                    minWidth.priority = .required
                    constraints.append(minWidth)
                }
                if button !== first {
                    let sameWidth = button.widthAnchor.constraint(equalTo: first.widthAnchor)
                    sameWidth.priority = .defaultHigh
                    constraints.append(sameWidth)
                }
            }
            return constraints
        }()

        inlineAddButton.configure(symbolName: "plus", accessibilityLabel: "Add pane tab", active: false, theme: theme, compact: true)
        inlineAddButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-add-\(paneStack.id.rawValue)")
        inlineAddButton.onPress = {
            try? onCreatePaneTab()
        }
        tabStrip.addArrangedSubview(inlineAddButton)

        pinnedAddButton.configure(symbolName: "plus", accessibilityLabel: "Add pane tab", active: false, theme: theme, compact: true)
        pinnedAddButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-add-pinned-\(paneStack.id.rawValue)")
        pinnedAddButton.onPress = {
            try? onCreatePaneTab()
        }
        pinnedAddButton.translatesAutoresizingMaskIntoConstraints = false
        pinnedAddButton.isHidden = true

        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.autohidesScrollers = true
        tabScrollView.drawsBackground = false
        tabScrollView.borderType = .noBorder
        tabScrollView.horizontalScrollElasticity = .allowed
        tabScrollView.verticalScrollElasticity = .none
        // Allow XCUITest to reach PaneTabButton children directly without the scroll view
        // intercepting the hit test.
        tabScrollView.setAccessibilityElement(false)
        tabScrollView.documentView = tabStrip
        tabScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: tabScrollView.contentView.topAnchor),
            tabStrip.bottomAnchor.constraint(equalTo: tabScrollView.contentView.bottomAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: tabScrollView.contentView.leadingAnchor),
            tabScrollView.heightAnchor.constraint(equalToConstant: ShellLayoutMetrics.paneHeaderHeight - 1),
        ])

        content.addArrangedSubview(tabScrollView)
        addSubview(pinnedAddButton)
        addSubview(content)
        NSLayoutConstraint.activate(tabWidthConstraints)

        let trailingToSuperview = content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        let trailingToPinned = content.trailingAnchor.constraint(equalTo: pinnedAddButton.leadingAnchor, constant: -4)
        self.contentTrailingToSuperviewConstraint = trailingToSuperview
        self.contentTrailingToPinnedConstraint = trailingToPinned

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            trailingToSuperview,
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            pinnedAddButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pinnedAddButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAddButtonMode()
    }

    func scrollActiveTabToVisible() {
        guard let activeButton = paneTabButtons.first(where: { $0.isActivePaneTab }) else {
            return
        }
        let targetRect = activeButton.convert(activeButton.bounds, to: tabStrip)
        tabScrollView.contentView.scrollToVisible(targetRect)
        tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
    }

    override func layout() {
        super.layout()
        updateAddButtonMode()
    }

    private func updateAddButtonMode() {
        guard bounds.width > 0 else {
            return
        }

        // Measure using the strip content width while inline add is present.
        let overflow = tabStrip.fittingSize.width > tabScrollView.contentView.bounds.width + 1

        inlineAddButton.isHidden = overflow
        pinnedAddButton.isHidden = !overflow

        contentTrailingToSuperviewConstraint?.isActive = !overflow
        contentTrailingToPinnedConstraint?.isActive = overflow
    }

    func insertionIndex(forWindowPoint windowPoint: NSPoint) -> Int {
        let pointInTabStrip = tabStrip.convert(windowPoint, from: nil)
        for (index, button) in paneTabButtons.enumerated() {
            let frame = button.convert(button.bounds, to: tabStrip)
            if pointInTabStrip.x < frame.midX {
                return index
            }
        }
        return paneTabButtons.count
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class PaneProgressOrbView: NSView {
    static let side = CGFloat(7)
    private static let pulseAnimationKey = "omux.progress.orb.pulse"

    private(set) var progressStateForTesting: PaneProgressState?
    private(set) var progressColorForTesting: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = Self.side / 2
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.side, height: Self.side)
    }

    func configure(progress: PaneProgress?, theme: WorkspaceShellTheme) {
        progressStateForTesting = progress?.state
        guard let progress else {
            isHidden = true
            progressColorForTesting = nil
            layer?.removeAnimation(forKey: Self.pulseAnimationKey)
            setAccessibilityLabel(nil)
            return
        }

        isHidden = false
        let progressColor = color(for: progress.state, theme: theme)
        progressColorForTesting = progressColor
        layer?.backgroundColor = progressColor.cgColor
        setAccessibilityLabel(accessibilityLabel(for: progress.state))
        updatePulse(for: progress.state)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func color(for state: PaneProgressState, theme: WorkspaceShellTheme) -> NSColor {
        switch state {
        case .active, .indeterminate:
            return theme.shell.accent
        case .error:
            return .systemRed
        case .needsInput:
            return .systemYellow
        case .paused:
            return .systemBlue
        }
    }

    private func accessibilityLabel(for state: PaneProgressState) -> String {
        switch state {
        case .active, .indeterminate:
            return "Pane working"
        case .error:
            return "Pane progress error"
        case .needsInput:
            return "Pane needs user input"
        case .paused:
            return "Pane idle"
        }
    }

    private func updatePulse(for state: PaneProgressState) {
        layer?.removeAnimation(forKey: Self.pulseAnimationKey)
        layer?.opacity = 1
        guard state == .active || state == .indeterminate else {
            return
        }
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false else {
            return
        }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.35
        pulse.toValue = 1
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: Self.pulseAnimationKey)
    }
}

private extension WorkspaceShellTheme {
    func iconColor(
        for icon: OmuxRenderedIcon,
        selected: Bool,
        fallback: NSColor? = nil
    ) -> NSColor {
        guard icon.colorsEnabled else {
            return fallback ?? (selected ? shell.selectedText : shell.textSecondary)
        }

        let themedColor = color(for: icon.colorToken)
        if selected, Self.contrastRatio(themedColor, shell.selection) < 3 {
            return fallback ?? shell.selectedText
        }
        return themedColor
    }
}

@MainActor
private final class PaneTabButton: NSControl, NSTextFieldDelegate {
    var onPress: (() -> Void)?
    var onDragStarted: ((PaneTabButton, NSEvent) -> Void)?
    var onDragMoved: ((PaneTabButton, NSEvent) -> Void)?
    var onDragEnded: ((PaneTabButton, NSEvent) -> Void)?
    var onDragCancelled: ((PaneTabButton) -> Void)?
    var canStartDrag: (() -> Bool)?
    var contextMenuProvider: (() -> NSMenu)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    /// Called when the user commits a non-empty inline rename.
    var onRename: ((String) -> Void)?
    /// Called when the user commits an empty inline rename (clears alias).
    var onClearAlias: (() -> Void)?

    private var isRenaming = false
    private var originalTitle: String = ""
    private weak var previousFirstResponder: NSResponder?
    private let titleLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let progressOrb = PaneProgressOrbView()
    private let closeButton = ChromePillButton()
    private let contentInsets = NSEdgeInsets(top: 0, left: 5, bottom: 0, right: 3)
    private let interItemSpacing = CGFloat(4)
    private let iconSpacing = CGFloat(4)
    private let symbolSide = CGFloat(12)
    private let showsClose: Bool
    private let currentTheme: WorkspaceShellTheme
    private var isActiveTab: Bool
    private let topBorderLayer = CALayer()
    private let renderedIcon: OmuxRenderedIcon?
    private let iconSymbolImage: NSImage?
    private let progress: PaneProgress?
    private let fullDisplayTitle: String
    var isActivePaneTab: Bool { isActiveTab }

    init(
        pane: Pane,
        active: Bool,
        theme: WorkspaceShellTheme,
        icon: OmuxRenderedIcon?,
        progress: PaneProgress?,
        showsClose: Bool,
        onClose: @escaping () -> Void
    ) {
        self.showsClose = showsClose
        self.currentTheme = theme
        self.isActiveTab = active
        self.renderedIcon = icon
        self.iconSymbolImage = icon?.symbolImage()
        self.progress = progress
        self.fullDisplayTitle = pane.displayTitle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        topBorderLayer.zPosition = 1
        layer?.addSublayer(topBorderLayer)
        identifier = NSUserInterfaceItemIdentifier("pane-tab-\(pane.id.rawValue)")
        setAccessibilityIdentifier("\(A11yID.paneTabPrefix)\(pane.id.rawValue)")
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
        setAccessibilityLabel(icon.map { "\($0.accessibilityLabel), \(fullDisplayTitle)" } ?? fullDisplayTitle)
        toolTip = fullDisplayTitle
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        progressOrb.identifier = NSUserInterfaceItemIdentifier("pane-tab-progress-\(pane.id.rawValue)")
        progressOrb.configure(progress: progress, theme: theme)
        addSubview(progressOrb)

        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.font = icon?.font ?? .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        iconLabel.lineBreakMode = .byClipping
        iconLabel.alignment = .center
        iconLabel.stringValue = icon?.text ?? ""
        iconLabel.toolTip = icon?.accessibilityLabel
         iconLabel.textColor = icon.flatMap { theme.iconColor(for: $0, selected: active) }
            ?? (active ? theme.shell.textPrimary : theme.shell.textSecondary)
        iconLabel.isHidden = icon == nil || iconSymbolImage != nil
        addSubview(iconLabel)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.symbolConfiguration = .init(pointSize: 11, weight: active ? .semibold : .medium)
        iconImageView.image = iconSymbolImage
         iconImageView.contentTintColor = icon.flatMap { theme.iconColor(for: $0, selected: active) }
            ?? (active ? theme.shell.textPrimary : theme.shell.textSecondary)
        iconImageView.toolTip = icon?.accessibilityLabel
        iconImageView.isHidden = iconSymbolImage == nil
        addSubview(iconImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.stringValue = pane.displayTitle
        titleLabel.toolTip = pane.displayTitle
         titleLabel.textColor = active ? theme.shell.textPrimary : theme.shell.textSecondary
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        if showsClose {
            closeButton.configure(
                symbolName: "xmark",
                accessibilityLabel: "Close \(fullDisplayTitle)",
                active: false,
                theme: theme,
                compact: true
            )
            closeButton.identifier = NSUserInterfaceItemIdentifier("pane-tab-close-\(pane.id.rawValue)")
            closeButton.onPress = onClose
            addSubview(closeButton)
        }

        updateVisualState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    // XCUITest determines isHittable for custom NSControl subclasses by checking
    // whether accessibilityPerformPress() is implemented. Without this override,
    // the button exists in the a11y tree but is not considered hittable by the
    // test framework — especially on headless CI runners where there is no key
    // window guarantee. Implementing this makes the element interactable for both
    // XCUITest and assistive technologies without changing first-responder behaviour.
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }

    override var isEnabled: Bool {
        didSet {
            updateVisualState()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ShellLayoutMetrics.paneHeaderHeight)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topBorderLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        CATransaction.commit()
        let contentLeft = contentInsets.left
        let contentRight = contentInsets.right

        var titleMinX = contentLeft
        if progress != nil {
            progressOrb.frame = NSRect(
                x: contentLeft,
                y: round((bounds.height - PaneProgressOrbView.side) / 2),
                width: PaneProgressOrbView.side,
                height: PaneProgressOrbView.side
            )
            titleMinX = progressOrb.frame.maxX + iconSpacing
        } else {
            progressOrb.frame = .zero
        }

        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconLabel.intrinsicContentSize
                iconLabel.frame = NSRect(
                    x: titleMinX,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconLabel.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                titleMinX = iconLabel.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: titleMinX,
                    y: round((bounds.height - symbolSide) / 2),
                    width: symbolSide,
                    height: symbolSide
                )
                iconImageView.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconLabel.frame = .zero
                titleMinX = iconImageView.frame.maxX + iconSpacing
            }
        } else {
            iconLabel.frame = .zero
            iconImageView.frame = .zero
        }

        let titleH = titleLabel.intrinsicContentSize.height
        let titleY = round((bounds.height - titleH) / 2)
        if showsClose {
            let closeSize = closeButton.intrinsicContentSize
            closeButton.frame = NSRect(
                x: bounds.width - contentRight - closeSize.width,
                y: round((bounds.height - closeSize.height) / 2),
                width: closeSize.width,
                height: closeSize.height
            )
            titleLabel.frame = NSRect(
                x: titleMinX,
                y: titleY,
                width: max(0, closeButton.frame.minX - interItemSpacing - titleMinX),
                height: titleH
            )
        } else {
            titleLabel.frame = NSRect(
                x: titleMinX,
                y: titleY,
                width: max(0, bounds.width - contentRight - titleMinX),
                height: titleH
            )
            closeButton.frame = .zero
        }
        titleLabel.lineBreakMode = .byTruncatingMiddle
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        // Double-click triggers rename regardless of drag capability.
        if event.clickCount == 2 {
            beginInlineRename()
            return
        }

        guard onDragStarted != nil || onDragMoved != nil || onDragEnded != nil else {
            onPress?()
            return
        }

        let initialLocation = convert(event.locationInWindow, from: nil)
        var didStartDragging = false

        // Once a drag starts, tracking must continue until mouse-up so drag cleanup always runs.
        while let nextEvent = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .keyDown where nextEvent.keyCode == 53: // Escape
                if didStartDragging {
                    onDragCancelled?(self)
                }
                return

            case .leftMouseDragged:
                let location = convert(nextEvent.locationInWindow, from: nil)
                let delta = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
                guard delta >= 4 else { continue }
                if !didStartDragging {
                    guard canStartDrag?() ?? true else { continue }
                    didStartDragging = true
                    onDragStarted?(self, nextEvent)
                }
                onDragMoved?(self, nextEvent)

            case .leftMouseUp:
                if didStartDragging {
                    onDragEnded?(self, nextEvent)
                } else {
                    onPress?()
                }
                return

            default:
                NSApp.postEvent(nextEvent, atStart: false)
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func beginInlineRename() {
        guard !isRenaming else { return }
        isRenaming = true
        originalTitle = fullDisplayTitle
        previousFirstResponder = window?.firstResponder
        titleLabel.isEditable = true
        titleLabel.isSelectable = true
        titleLabel.isBezeled = false
        titleLabel.focusRingType = .none
        titleLabel.drawsBackground = false
        titleLabel.delegate = self
        window?.makeFirstResponder(titleLabel)
        titleLabel.currentEditor()?.selectAll(nil)
    }

    private func commitInlineRename() {
        guard isRenaming else { return }
        let newName = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        endInlineRename()
        if newName.isEmpty {
            onClearAlias?()
        } else {
            onRename?(newName)
        }
    }

    private func cancelInlineRename() {
        guard isRenaming else { return }
        titleLabel.stringValue = originalTitle
        endInlineRename()
    }

    private func endInlineRename() {
        guard isRenaming else { return }
        isRenaming = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.delegate = nil
        window?.makeFirstResponder(previousFirstResponder)
        previousFirstResponder = nil
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        MainActor.assumeIsolated {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitInlineRename()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelInlineRename()
                return true
            }
            return false
        }
    }

    nonisolated func controlTextDidEndEditing(_ obj: Notification) {
        MainActor.assumeIsolated {
            if isRenaming {
                commitInlineRename()
            }
        }
    }

    func setActive(_ active: Bool) {
        guard active != isActiveTab else { return }
        isActiveTab = active
        titleLabel.font = .systemFont(ofSize: 11, weight: active ? .semibold : .medium)
        updateVisualState()
    }

    private func updateVisualState() {
        titleLabel.textColor = isActiveTab ? currentTheme.shell.textPrimary : currentTheme.shell.textSecondary
        let iconColor = renderedIcon.flatMap { currentTheme.iconColor(for: $0, selected: isActiveTab) }
            ?? titleLabel.textColor
        iconLabel.textColor = iconColor
        iconImageView.contentTintColor = iconColor
        if isActiveTab {
            layer?.backgroundColor = currentTheme.shell.paneCardBackground.cgColor
            topBorderLayer.backgroundColor = currentTheme.shell.border.cgColor
            topBorderLayer.isHidden = false
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            topBorderLayer.isHidden = true
        }
        alphaValue = isEnabled ? 1.0 : 0.4
    }
}

@MainActor
private class ChromePillButton: NSControl {
    var onPress: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    private let titleLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private var compact = false
    private var contentInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    private var title: String?
    private var symbolName: String?
    private var accessibilityLabel: String?
    private var isActive = false
    private var isHovered = false
    private var currentTheme = WorkspaceShellTheme.defaultTheme

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        imageView.isHidden = true
        addSubview(imageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, active: Bool, theme: WorkspaceShellTheme, compact: Bool = false) {
        self.title = title
        symbolName = nil
        accessibilityLabel = title
        setAccessibilityLabel(title)
        imageView.isHidden = true
        titleLabel.isHidden = false
        titleLabel.stringValue = title
        applyConfiguration(active: active, theme: theme, compact: compact)
    }

    func configure(
        symbolName: String,
        accessibilityLabel: String,
        active: Bool,
        theme: WorkspaceShellTheme,
        compact: Bool = false
    ) {
        title = nil
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
        setAccessibilityLabel(accessibilityLabel)
        titleLabel.isHidden = true
        imageView.isHidden = false
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        applyConfiguration(active: active, theme: theme, compact: compact)
    }

    func applyTheme(_ theme: WorkspaceShellTheme) {
        applyConfiguration(active: isActive, theme: theme, compact: compact)
    }

    override var isEnabled: Bool {
        didSet {
            updateVisualState()
        }
    }

    private func applyConfiguration(active: Bool, theme: WorkspaceShellTheme, compact: Bool) {
        self.compact = compact
        isActive = active
        currentTheme = theme
        self.compact = compact
        contentInsets = NSEdgeInsets(top: compact ? 2 : 4, left: compact ? 6 : 8, bottom: compact ? 2 : 4, right: compact ? 6 : 8)
        titleLabel.font = .systemFont(ofSize: compact ? 11 : 12, weight: active ? .semibold : .medium)
        layer?.cornerRadius = compact ? 3 : 4
        imageView.symbolConfiguration = .init(pointSize: compact ? 11 : 12, weight: active ? .semibold : .medium)
        updateVisualState()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func updateVisualState() {
        let foreground = isActive ? currentTheme.shell.selectedText : currentTheme.shell.textSecondary
        titleLabel.textColor = foreground
        imageView.contentTintColor = foreground
        let background: NSColor
        if isActive {
            background = currentTheme.shell.selection
        } else if isHovered {
            background = NSColor.labelColor.withAlphaComponent(0.15)
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        alphaValue = isEnabled ? 1 : 0.4
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        guard !bounds.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize == .zero {
            isHovered = false
            updateVisualState()
        }
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateVisualState()
    }

    override var intrinsicContentSize: NSSize {
        let contentSize: NSSize
        if let title {
            titleLabel.stringValue = title
            contentSize = titleLabel.intrinsicContentSize
        } else {
            let symbolSide = compact ? CGFloat(11) : CGFloat(12)
            contentSize = NSSize(width: symbolSide, height: symbolSide)
        }
        return NSSize(
            width: contentSize.width + contentInsets.left + contentInsets.right,
            height: max(contentSize.height + contentInsets.top + contentInsets.bottom, compact ? 18 : 24)
        )
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
        let contentBounds = bounds.insetBy(dx: contentInsets.left, dy: contentInsets.top)
        if title == nil {
            let symbolSide = compact ? CGFloat(11) : CGFloat(12)
            imageView.frame = NSRect(
                x: round((bounds.width - symbolSide) / 2),
                y: round((bounds.height - symbolSide) / 2),
                width: symbolSide,
                height: symbolSide
            )
            titleLabel.frame = .zero
        } else {
            titleLabel.frame = contentBounds
            imageView.frame = .zero
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        onPress?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

}

@MainActor
final class SidebarItemButton: NSView, NSTextFieldDelegate {
    var onPress: (() -> Void)?
    var onToggleExpansion: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onBeginRename: (() -> Void)?
    var workspaceID: WorkspaceID?
    var onDragStarted: ((SidebarItemButton, NSEvent) -> Void)?
    var onDragMoved: ((SidebarItemButton, NSEvent) -> Void)?
    var onDragEnded: ((SidebarItemButton, NSEvent) -> Void)?
    var contextMenuProvider: (() -> NSMenu?)? {
        didSet {
            menu = contextMenuProvider?()
        }
    }
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let disclosureImageView = NSImageView()
    private let iconField = NSTextField(labelWithString: "")
    private let iconImageView = NSImageView()
    private let progressOrb = PaneProgressOrbView()
    private var leadingInset: CGFloat = 12
    private var textLeadingInset: CGFloat = 12
    private var renderedIcon: OmuxRenderedIcon?
    private var iconSymbolImage: NSImage?
    private var iconSide = CGFloat(13)
    private var progress: PaneProgress?
    private var showsDisclosure = false
    private var isActive = false
    private var isRenaming = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        progressOrb.identifier = NSUserInterfaceItemIdentifier("sidebar-pane-progress")
        addSubview(progressOrb)

        disclosureImageView.isHidden = true
        addSubview(disclosureImageView)

        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        iconField.maximumNumberOfLines = 1
        iconField.lineBreakMode = .byClipping
        iconField.alignment = .center
        iconField.isBezeled = false
        iconField.drawsBackground = false
        iconField.isEditable = false
        iconField.isSelectable = false
        addSubview(iconField)

        iconImageView.isHidden = true
        addSubview(iconImageView)

        subtitleField.maximumNumberOfLines = 1
        subtitleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.isBezeled = false
        subtitleField.drawsBackground = false
        subtitleField.isEditable = false
        subtitleField.isSelectable = false
        addSubview(subtitleField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(item: SidebarItem, theme: WorkspaceShellTheme) {
        switch item.kind {
        case .workspace:
            titleField.font = .systemFont(ofSize: 13, weight: .semibold)
            leadingInset = 6
            subtitleField.font = .systemFont(ofSize: 11, weight: .regular)
        case .terminal:
            titleField.font = .systemFont(ofSize: 10, weight: .regular)
            subtitleField.font = .systemFont(ofSize: 10, weight: .regular)
            leadingInset = 22
        }

        titleField.stringValue = item.title
        isActive = item.isActive
        progress = item.progress
        progressOrb.configure(progress: item.progress, theme: theme)
        renderedIcon = item.icon
        iconSymbolImage = item.icon?.symbolImage()
        iconSide = item.kind == .workspace ? 13 : 11
        showsDisclosure = item.kind == .workspace && item.isExpanded != nil
        let disclosureSymbol = item.isExpanded == false ? "chevron.right" : "chevron.down"
        disclosureImageView.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        disclosureImageView.image = NSImage(systemSymbolName: disclosureSymbol, accessibilityDescription: nil)
        disclosureImageView.isHidden = !showsDisclosure
        disclosureImageView.setAccessibilityLabel(item.isExpanded == false ? "Expand workspace panes" : "Collapse workspace panes")
        iconField.stringValue = item.icon?.text ?? ""
        iconField.font = item.icon?.font ?? .systemFont(ofSize: item.kind == .workspace ? 13 : 11, weight: .medium)
        iconField.isHidden = item.icon == nil || iconSymbolImage != nil
        iconField.toolTip = item.icon?.accessibilityLabel
        iconImageView.symbolConfiguration = .init(pointSize: iconSide, weight: item.kind == .workspace ? .semibold : .medium)
        iconImageView.image = iconSymbolImage
        iconImageView.isHidden = iconSymbolImage == nil
        iconImageView.toolTip = item.icon?.accessibilityLabel
        setAccessibilityLabel(item.icon.map { "\($0.accessibilityLabel), \(item.title)" } ?? item.title)
        if item.kind == .workspace {
            setAccessibilityIdentifier("\(A11yID.workspaceItemPrefix)\(item.identifier)")
            setAccessibilityRole(.button)
            setAccessibilityElement(true)
        }
        titleField.textColor = item.kind == .terminal
            ? theme.shell.textMuted
            : (item.isActive ? theme.shell.selectedText : theme.shell.textSecondary)
        let iconColor = item.icon.map {
            theme.iconColor(
                for: $0,
                selected: item.isActive,
                fallback: titleField.textColor ?? theme.shell.textSecondary
            )
        } ?? titleField.textColor
        iconField.textColor = iconColor
        iconImageView.contentTintColor = iconColor
        disclosureImageView.contentTintColor = item.isActive ? theme.shell.selectedText : theme.shell.textMuted
        subtitleField.stringValue = item.subtitle ?? ""
        subtitleField.textColor = theme.shell.textMuted
        subtitleField.isHidden = item.subtitle == nil
        switch item.kind {
        case .workspace:
            layer?.backgroundColor = item.isActive
                ? theme.shell.selection.cgColor
                : NSColor.clear.cgColor
            layer?.cornerRadius = 3
        case .terminal:
            layer?.backgroundColor = item.isActive
                ? theme.shell.selection.withAlphaComponent(0.28).cgColor
                : NSColor.clear.cgColor
            layer?.cornerRadius = 3
        }
        layer?.borderWidth = 0
        layer?.borderColor = nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let trailingInset: CGFloat = 12
        let iconSpacing: CGFloat = renderedIcon == nil ? 0 : 6
        var textX = leadingInset
        if progress != nil {
            let progressX = max(0, leadingInset - PaneProgressOrbView.side - 5)
            progressOrb.frame = NSRect(
                x: progressX,
                y: round((bounds.height - PaneProgressOrbView.side) / 2),
                width: PaneProgressOrbView.side,
                height: PaneProgressOrbView.side
            )
        } else {
            progressOrb.frame = .zero
        }
        if showsDisclosure {
            let disclosureSide: CGFloat = 11
            disclosureImageView.frame = NSRect(
                x: textX,
                y: round((bounds.height - disclosureSide) / 2),
                width: disclosureSide,
                height: disclosureSide
            )
            textX = disclosureImageView.frame.maxX + 4
        } else {
            disclosureImageView.frame = .zero
        }
        if let renderedIcon {
            if iconSymbolImage == nil {
                let iconSize = iconField.intrinsicContentSize
                iconField.frame = NSRect(
                    x: textX,
                    y: round((bounds.height - iconSize.height) / 2),
                    width: iconSize.width,
                    height: iconSize.height
                )
                iconField.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconImageView.frame = .zero
                textX = iconField.frame.maxX + iconSpacing
            } else {
                iconImageView.frame = NSRect(
                    x: textX,
                    y: round((bounds.height - iconSide) / 2),
                    width: iconSide,
                    height: iconSide
                )
                iconImageView.setAccessibilityLabel(renderedIcon.accessibilityLabel)
                iconField.frame = .zero
                textX = iconImageView.frame.maxX + iconSpacing
            }
        } else {
            iconField.frame = .zero
            iconImageView.frame = .zero
        }
        textLeadingInset = textX
        let labelWidth = bounds.width - textLeadingInset - trailingInset
        let titleHeight = titleField.intrinsicContentSize.height
        if subtitleField.isHidden {
            titleField.frame = NSRect(
                x: textLeadingInset,
                y: (bounds.height - titleHeight) / 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = .zero
        } else {
            let subtitleHeight = subtitleField.intrinsicContentSize.height
            let totalHeight = titleHeight + subtitleHeight + 2
            let startY = (bounds.height - totalHeight) / 2
            titleField.frame = NSRect(
                x: textLeadingInset,
                y: startY + subtitleHeight + 2,
                width: max(labelWidth, 0),
                height: titleHeight
            )
            subtitleField.frame = NSRect(
                x: textLeadingInset,
                y: startY,
                width: max(labelWidth, 0),
                height: subtitleHeight
            )
        }
    }

    override var acceptsFirstResponder: Bool { isRenaming }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if showsDisclosure,
           disclosureImageView.frame.insetBy(dx: -5, dy: -5).contains(convert(event.locationInWindow, from: nil)) {
            onToggleExpansion?()
            return
        }

        guard onDragStarted != nil || onDragMoved != nil || onDragEnded != nil else {
            if event.clickCount == 2, onRename != nil {
                onBeginRename?()
            } else {
                onPress?()
            }
            return
        }

        let initialLocation = convert(event.locationInWindow, from: nil)
        var didStartDragging = false

        while let nextEvent = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp, .leftMouseDown],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDown:
                if nextEvent.clickCount == 2, onRename != nil {
                    onBeginRename?()
                }
                return

            case .leftMouseDragged:
                let location = convert(nextEvent.locationInWindow, from: nil)
                let delta = hypot(location.x - initialLocation.x, location.y - initialLocation.y)
                guard delta >= 4 else {
                    continue
                }

                if didStartDragging == false {
                    didStartDragging = true
                    onDragStarted?(self, nextEvent)
                }
                onDragMoved?(self, nextEvent)

            case .leftMouseUp:
                if didStartDragging {
                    onDragEnded?(self, nextEvent)
                    return
                }
                // Only wait for a possible double-click if this workspace is already active.
                // If it's inactive, fire onPress immediately — no delay on workspace switching.
                if onRename != nil, isActive {
                    let doubleClickInterval = NSEvent.doubleClickInterval
                    if let secondClick = window?.nextEvent(
                        matching: [.leftMouseDown],
                        until: Date(timeIntervalSinceNow: doubleClickInterval),
                        inMode: .eventTracking,
                        dequeue: true
                    ) {
                        if secondClick.clickCount == 2 {
                            onBeginRename?()
                        } else {
                            onPress?()
                            NSApp.postEvent(secondClick, atStart: true)
                        }
                    } else {
                        onPress?()
                    }
                    return
                }
                onPress?()
                return

            default:
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu ?? contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func beginInlineRename() {
        guard !isRenaming else { return }
        isRenaming = true

        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.isBezeled = false
        titleField.focusRingType = .none
        titleField.drawsBackground = false
        titleField.delegate = self
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    private func commitInlineRename() {
        guard isRenaming else { return }
        let newName = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        endInlineRename()
        if !newName.isEmpty {
            onRename?(newName)
        }
    }

    private func cancelInlineRename() {
        endInlineRename()
    }

    private func endInlineRename() {
        guard isRenaming else { return }
        isRenaming = false
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.delegate = nil
        window?.makeFirstResponder(nil)
    }

    func setDropTarget(_ isDropTarget: Bool, theme: WorkspaceShellTheme?) {
        guard let theme else {
            return
        }
        layer?.borderWidth = isDropTarget ? 1 : 0
        layer?.borderColor = isDropTarget ? theme.shell.selection.cgColor : nil
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        MainActor.assumeIsolated {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitInlineRename()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelInlineRename()
                return true
            }
            return false
        }
    }

    nonisolated func controlTextDidEndEditing(_ obj: Notification) {
        MainActor.assumeIsolated {
            // only commit if we initiated this — avoids acting on unrelated end-editing events
            if isRenaming {
                commitInlineRename()
            }
        }
    }

    func setDraggingPreview(_ isDragging: Bool, theme: WorkspaceShellTheme?) {
        layer?.shadowOpacity = isDragging ? 0.18 : 0
        layer?.shadowRadius = isDragging ? 8 : 0
        layer?.shadowOffset = isDragging ? CGSize(width: 0, height: -2) : .zero
        layer?.shadowColor = theme?.shell.selection.cgColor
    }
}

@MainActor
private final class MenuActionTrampoline: NSObject {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func performAction(_ sender: Any?) {
        _ = sender
        handler()
    }
}

private extension NSMenuItem {
    @discardableResult
    @MainActor
    func onSelect(_ handler: @escaping () -> Void) -> NSMenuItem {
        let trampoline = MenuActionTrampoline(handler: handler)
        target = trampoline
        action = #selector(MenuActionTrampoline.performAction(_:))
        representedObject = trampoline
        return self
    }
}
