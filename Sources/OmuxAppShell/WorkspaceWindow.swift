import AppKit
import OmuxAIStatusPlugin
import OmuxConfig
import OmuxControlPlane
import OmuxCore
import OmuxTerminalBridge
import OmuxVault
import QuartzCore
import WebKit

enum ShellLayoutMetrics {
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
        replaceTrackingArea(&hoverTrackingArea, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect])
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
class WorkspaceWindow: NSWindow {
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
        initialSidebar: OmuxConfigUI.Sidebar = OmuxConfigUI.Sidebar(),
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
            initialSidebar: initialSidebar,
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
        let hydratedWorkspace: Workspace
        do {
            hydratedWorkspace = try controller.ensureVisibleTerminalSurfaces(
                for: displayedWorkspace.id,
                presentationState: presentationState
            ) ?? displayedWorkspace
        } catch {
            fputs("warning: failed to ensure visible terminal surfaces: \(error)\n", stderr)
            hydratedWorkspace = displayedWorkspace
        }
        window?.title = hydratedWorkspace.name
        rootViewController.update(workspace: hydratedWorkspace)
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

    func updateSidebar(_ sidebar: OmuxConfigUI.Sidebar) {
        rootViewController.updateSidebar(sidebar)
    }

    func setPaneMetadataRows(
        paneID: PaneID,
        row1: String?,
        row2: String?,
        row3: String?,
        source: String? = nil
    ) -> Bool {
        rootViewController.setPaneMetadataRows(
            paneID: paneID,
            row1: row1,
            row2: row2,
            row3: row3,
            source: source
        )
    }

    func clearPaneMetadataRows(paneID: PaneID, source: String? = nil) -> Bool {
        rootViewController.clearPaneMetadataRows(paneID: paneID, source: source)
    }

    func toggleSidebarVisibility() {
        rootViewController.toggleSidebarVisibility()
    }

    func toggleVaultSidebarVisibility() {
        rootViewController.toggleVaultSidebar()
    }

    func setAgentSessionsVisibility(_ isVisible: Bool) {
        rootViewController.setVaultSidebarVisibility(isVisible)
    }

    func toggleAgentSessionsVisibility() {
        rootViewController.toggleAgentSessionsPanel()
    }

    func toggleWorktreesVisibility() {
        rootViewController.toggleWorktreesPanel()
    }

    func presentAgentSessionsPalette(keyBindings: OpenMUXKeyBindingRegistry) {
        rootViewController.presentAgentSessionsPalette(keyBindings: keyBindings)
    }

    func presentRenameWorkspacePrompt(workspaceID: WorkspaceID? = nil) {
        rootViewController.presentRenameWorkspacePrompt(workspaceID: workspaceID)
    }

    func presentWorkspaceRootPrompt(workspaceID: WorkspaceID? = nil) {
        rootViewController.presentWorkspaceRootPrompt(workspaceID: workspaceID)
    }

    func resetWorkspaceRootToAutomatic(workspaceID: WorkspaceID? = nil) {
        rootViewController.resetWorkspaceRootToAutomatic(workspaceID: workspaceID)
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

    func presentWorkspaceRestoreBanner(_ entry: RecentlyClosedWorkspaceEntry, controller: WorkspaceController) {
        rootViewController.presentWorkspaceRestoreBanner(entry, controller: controller)
    }
}
