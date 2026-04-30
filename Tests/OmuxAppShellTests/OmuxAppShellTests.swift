import AppKit
import OmuxConfig
import OmuxTheme
import Foundation
import XCTest
@testable import OmuxAppShell
@testable import OmuxCore
@testable import OmuxHooks
@testable import OmuxTerminalBridge

final class OmuxAppShellTests: XCTestCase {
    func testWorkspaceControllerCreatesTabsAndSplits() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertEqual(workspace.tabs[0].panes.count, 1)

        let withNewTab = try XCTUnwrap(controller.createTab())
        XCTAssertEqual(withNewTab.tabs.count, 2)
        XCTAssertEqual(withNewTab.focusedTab?.panes.count, 1)

        let withSplit = try XCTUnwrap(controller.splitFocusedPane())
        XCTAssertEqual(withSplit.focusedTab?.panes.count, 2)
        XCTAssertEqual(withSplit.focusedTab?.focusedPaneID, withSplit.focusedTab?.panes.last?.id)
    }

    func testWorkspaceControllerCanSplitDown() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let withVerticalSplit = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))

        XCTAssertEqual(withVerticalSplit.focusedTab?.panes.count, 2)
    }

    func testWorkspaceControllerSupportsNestedSplitLayouts() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitDown = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let bottomPaneID = try XCTUnwrap(splitDown.focusedTab?.focusedPaneID)

        _ = controller.focus(paneID: bottomPaneID)
        let nestedLayout = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))

        XCTAssertEqual(nestedLayout.focusedTab?.panes.count, 3)

        guard case .split(axis: .rows, let rootChildren)? = nestedLayout.focusedTab?.rootLayout else {
            return XCTFail("expected a row split at the root")
        }

        XCTAssertEqual(rootChildren.count, 2)
        guard case .split(axis: .columns, let nestedChildren) = rootChildren[1] else {
            return XCTFail("expected the lower pane to become a nested column split")
        }

        XCTAssertEqual(nestedChildren.count, 2)
        guard case .paneStack = rootChildren[0] else {
            return XCTFail("expected the upper region to remain a pane stack")
        }
        guard case .paneStack = nestedChildren[0] else {
            return XCTFail("expected nested children to be pane stacks")
        }
        guard case .paneStack = nestedChildren[1] else {
            return XCTFail("expected nested children to be pane stacks")
        }
    }

    func testWorkspaceControllerCreatesAndClosesPaneTabsInFocusedStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalPaneID = try XCTUnwrap(workspace.focusedPane?.id)

        let withPaneTab = try XCTUnwrap(controller.createPaneTab())
        XCTAssertEqual(withPaneTab.focusedTab?.panes.count, 2)
        XCTAssertEqual(withPaneTab.focusedTab?.paneStacks.count, 1)
        XCTAssertNotEqual(withPaneTab.focusedTab?.focusedPaneID, originalPaneID)

        let focusedPaneTabID = try XCTUnwrap(withPaneTab.focusedTab?.focusedPaneID)
        let refocused = try XCTUnwrap(controller.focusPaneTab(paneID: originalPaneID))
        XCTAssertEqual(refocused.focusedTab?.focusedPaneID, originalPaneID)

        let closed = try XCTUnwrap(controller.closePaneTab(paneID: focusedPaneTabID))
        XCTAssertEqual(closed.focusedTab?.panes.count, 1)
        XCTAssertEqual(closed.focusedTab?.focusedPaneID, originalPaneID)
    }

    func testWorkspaceControllerRemovesActivePaneByClosingSinglePaneTab() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let workspaceWithSecondTab = try XCTUnwrap(controller.createTab())
        XCTAssertEqual(workspaceWithSecondTab.tabs.count, 2)
        XCTAssertTrue(controller.canRemoveActivePane())

        let updatedWorkspace = try XCTUnwrap(controller.removeActivePane())
        XCTAssertEqual(updatedWorkspace.tabs.count, 1)
        XCTAssertEqual(updatedWorkspace.focusedTab?.title, "Main")
        XCTAssertFalse(controller.canRemoveActivePane())
    }

    func testWorkspaceControllerRemovesActivePaneAndCollapsesSplit() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        XCTAssertEqual(splitWorkspace.focusedTab?.panes.count, 2)

        let updatedWorkspace = try XCTUnwrap(controller.removeActivePane())
        XCTAssertEqual(updatedWorkspace.focusedTab?.panes.count, 1)

        guard case .paneStack? = updatedWorkspace.focusedTab?.rootLayout else {
            return XCTFail("expected split layout to collapse back to a single pane stack")
        }
    }

    func testWorkspaceControllerDeletesActiveWorkspaceWhenAnotherExists() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        XCTAssertNotEqual(firstWorkspace.id, secondWorkspace.id)
        XCTAssertTrue(controller.canDeleteActiveWorkspace())

        let survivingWorkspace = try XCTUnwrap(controller.deleteActiveWorkspace())
        XCTAssertEqual(survivingWorkspace.id, firstWorkspace.id)
        XCTAssertFalse(controller.canDeleteActiveWorkspace())
    }

    func testWorkspaceControllerCreatesUniquelyNamedWorkspaces() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertEqual(firstWorkspace.name, "tmp")
        XCTAssertEqual(secondWorkspace.name, "tmp 2")
    }

    func testWorkspaceControllerCanRenameWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let renamedWorkspace = try XCTUnwrap(controller.renameWorkspace(workspace.id, to: "Project Alpha"))

        XCTAssertEqual(renamedWorkspace.name, "Project Alpha")
        XCTAssertEqual(controller.activeWorkspace()?.name, "Project Alpha")
    }

    func testRunCommandTargetsLiveSession() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "printf 'hello'"))
    }

    @MainActor
    func testRunCommandPreservesSessionContinuity() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        let paneID = try XCTUnwrap(workspace.focusedPane?.id)

        let expectation = expectation(description: "same session receives multiple commands")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: paneID) { snapshot in
            if snapshot.renderedText.contains("/\n") {
                expectation.fulfill()
            }
        }

        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "cd /"))
        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "pwd"))

        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: paneID, token: token)
    }

    @MainActor
    func testWorkspaceWindowHostsBridgeProvidedTerminalPaneView() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        XCTAssertNotNil(findHostedTerminalPaneView(in: rootView))
    }

    @MainActor
    func testWorkspaceWindowUsesTerminalNativeShellChrome() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.createTab()
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        XCTAssertNotNil(findView(ofType: WorkspaceSidebarView.self, in: rootView))
        XCTAssertNotNil(findView(ofType: WorkspaceTopBarView.self, in: rootView))
        XCTAssertNotNil(findView(ofType: WorkspaceCanvasView.self, in: rootView))
    }

    @MainActor
    func testWorkspaceWindowMovesTabNavigationIntoSidebar() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createTab())
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))
        let topBar = try XCTUnwrap(findView(ofType: WorkspaceTopBarView.self, in: rootView))

        XCTAssertTrue(findLabel(withString: "tmp", in: sidebar))
        XCTAssertFalse(findLabel(withString: "New Tab", in: topBar))
        XCTAssertFalse(findLabel(withString: "SESSIONS", in: sidebar))
    }

    @MainActor
    func testWorkspaceWindowShowsVisibleSidebarNavigation() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createTab())
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let wsLabel = try XCTUnwrap(findLabelView(withString: "tmp", in: sidebar))
        let wsButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: wsLabel))
        XCTAssertNotNil(wsButton)
        XCTAssertTrue(findLabel(withString: "+", in: sidebar))
    }

    @MainActor
    func testConfigurationCoordinatorReloadPublishesThemeChange() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = home.appendingPathComponent("config.toml")
        let themesDirectoryURL = home.appendingPathComponent("themes", isDirectory: true)
        let generatedURL = home.appendingPathComponent("generated/ghostty", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        schema = 1

        [theme]
        name = "monokai-soda"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let evaluator = OmuxConfigurationEvaluator(
            configLoader: OmuxConfigLoader(configURL: configURL),
            themeRegistry: OmuxThemeRegistry(userThemesDirectoryURL: themesDirectoryURL),
            compiler: OmuxThemeCompiler(generatedGhosttyDirectoryURL: generatedURL)
        )
        let prepared = OpenMUXConfigurationCoordinator.prepareInitialState(evaluator: evaluator)
        let coordinator = OpenMUXConfigurationCoordinator(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            initialState: prepared,
            evaluator: evaluator
        )

        let expectation = expectation(description: "theme changed")
        coordinator.onThemeChange = { theme in
            if theme.identifier == "nord" {
                expectation.fulfill()
            }
        }

        try """
        schema = 1

        [theme]
        name = "nord"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = coordinator.reload()

        XCTAssertTrue(result.applied)
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testWorkspaceWindowSidebarTracksMultipleWorkspaces() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        let windowController = WorkspaceWindowController(workspace: secondWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        XCTAssertTrue(findLabel(withString: "WORKSPACES · 2", in: sidebar))
        XCTAssertGreaterThanOrEqual(findViews(ofType: SidebarItemButton.self, in: sidebar).count, 2)
    }

    @MainActor
    func testWorkspaceWindowTopBarShowsWorkspaceName() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let renamedWorkspace = try XCTUnwrap(controller.renameWorkspace(workspace.id, to: "Project Alpha"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let topBar = try XCTUnwrap(findView(ofType: WorkspaceTopBarView.self, in: rootView))

        XCTAssertTrue(findLabel(withString: "Project Alpha", in: topBar))
        XCTAssertFalse(findLabel(withString: "Main", in: topBar))
    }

    @MainActor
    func testWorkspaceWindowRendersHorizontalSplitForSplitRight() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let windowController = WorkspaceWindowController(workspace: splitWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        windowController.showWindow(nil)
        let rootView = try XCTUnwrap(window.contentViewController?.view)

        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let paneCards = findViews(ofType: PaneCardView.self, in: rootView)
        XCTAssertEqual(paneCards.count, 2)
        let firstFrame = paneCards[0].convert(paneCards[0].bounds, to: rootView)
        let secondFrame = paneCards[1].convert(paneCards[1].bounds, to: rootView)
        XCTAssertEqual(firstFrame.minY, secondFrame.minY, accuracy: 1)
        XCTAssertNotEqual(firstFrame.minX, secondFrame.minX)
    }

    @MainActor
    func testWorkspaceWindowUsesDedicatedPaneHeaderChrome() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        XCTAssertNotNil(findView(ofType: PaneHeaderView.self, in: rootView))
        XCTAssertNil(findView(ofType: NSSegmentedControl.self, in: rootView))
    }

    func testBuiltInThemesIncludeDefaultAndCuratedPresets() {
        let identifiers = Set(WorkspaceShellTheme.builtInPresets.map(\.identifier))

        XCTAssertTrue(identifiers.contains("monokai-soda"))
        XCTAssertTrue(identifiers.contains("catppuccin"))
        XCTAssertTrue(identifiers.contains("dracula"))
        XCTAssertTrue(identifiers.contains("nord"))
        XCTAssertTrue(identifiers.contains("gruvbox"))
        XCTAssertTrue(identifiers.contains("one-dark"))
        XCTAssertTrue(identifiers.contains("solarized-dark"))
        XCTAssertTrue(identifiers.contains("solarized-light"))
        XCTAssertEqual(WorkspaceShellTheme.builtInPresets.count, identifiers.count)
        XCTAssertEqual(WorkspaceShellTheme.defaultTheme.identifier, "monokai-soda")
        XCTAssertNotEqual(WorkspaceShellTheme.defaultTheme.terminalPalette, WorkspaceShellTheme.builtInPresets.first(where: { $0.identifier == "catppuccin" })?.terminalPalette)
    }

    @MainActor
    private func findHostedTerminalPaneView(in view: NSView) -> HostedTerminalPaneView? {
        if let hosted = view as? HostedTerminalPaneView {
            return hosted
        }

        for subview in view.subviews {
            if let hosted = findHostedTerminalPaneView(in: subview) {
                return hosted
            }
        }

        return nil
    }

    @MainActor
    private func findView<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let matched = view as? T {
            return matched
        }

        for subview in view.subviews {
            if let matched = findView(ofType: type, in: subview) {
                return matched
            }
        }

        return nil
    }

    @MainActor
    private func findLabel(withString string: String, in view: NSView) -> Bool {
        if let label = view as? NSTextField, label.stringValue == string {
            return true
        }

        return view.subviews.contains { findLabel(withString: string, in: $0) }
    }

    @MainActor
    private func findLabelView(withString string: String, in view: NSView) -> NSTextField? {
        if let label = view as? NSTextField, label.stringValue == string {
            return label
        }

        for subview in view.subviews {
            if let label = findLabelView(withString: string, in: subview) {
                return label
            }
        }

        return nil
    }

    @MainActor
    private func findViews<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
        var matches: [T] = []
        if let matched = view as? T {
            matches.append(matched)
        }
        for subview in view.subviews {
            matches.append(contentsOf: findViews(ofType: type, in: subview))
        }
        return matches
    }

    @MainActor
    private func findAncestor<T: NSView>(ofType type: T.Type, for view: NSView) -> T? {
        var current = view.superview
        while let candidate = current {
            if let matched = candidate as? T {
                return matched
            }
            current = candidate.superview
        }
        return nil
    }
}
