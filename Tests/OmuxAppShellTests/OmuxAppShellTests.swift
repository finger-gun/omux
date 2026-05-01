import AppKit
import OmuxConfig
import OmuxTheme
import Foundation
import XCTest
@testable import OmuxControlPlane
@testable import OmuxAppShell
@testable import OmuxCore
@testable import OmuxHooks
@testable import OmuxTerminalBridge

final class OmuxAppShellTests: XCTestCase {
    @MainActor
    private final class InMemorySidebarVisibilityStore: WorkspaceSidebarVisibilityStoring {
        var isSidebarVisible: Bool

        init(isSidebarVisible: Bool = true) {
            self.isSidebarVisible = isSidebarVisible
        }
    }

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

        XCTAssertEqual(firstWorkspace.name, "Workspace 1")
        XCTAssertEqual(secondWorkspace.name, "Workspace 2")
    }

    func testWorkspaceControllerReusesLowestAvailableGeneratedWorkspaceName() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        _ = try controller.createWorkspace()
        _ = try controller.closeWorkspace(secondWorkspace.id)

        let replacementWorkspace = try controller.createWorkspace()
        XCTAssertEqual(replacementWorkspace.name, "Workspace 2")
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

    func testWorkspaceControllerCanRemoveCustomWorkspaceName() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.renameWorkspace(workspace.id, to: "Project Alpha")
        let resetWorkspace = try XCTUnwrap(controller.removeCustomWorkspaceName(workspace.id))

        XCTAssertEqual(resetWorkspace.name, "Workspace 1")
        XCTAssertNil(resetWorkspace.customName)
    }

    func testWorkspaceControllerRestoresPersistedWorkspacesWithFreshTerminalState() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let firstPane = try XCTUnwrap(firstWorkspace.focusedPane)
        let firstSurfaceID = try XCTUnwrap(bridge.surface(for: firstPane.id)?.runtimeSurfaceID)
        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: firstSurfaceID)
        runtime.emit(.progressReported(state: .active, progress: 42), on: firstSurfaceID)

        _ = try controller.renameWorkspace(firstWorkspace.id, to: "Client Shell")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let secondWorkspace = try controller.createWorkspace()
        _ = controller.focus(paneID: try XCTUnwrap(splitWorkspace.focusedPane?.id))

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let restoredController = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let restoredActiveWorkspace = try XCTUnwrap(restoredController.restorePersistedState(snapshot))
        let restoredWorkspaces = restoredController.allWorkspaces()

        XCTAssertEqual(restoredWorkspaces.count, 2)
        XCTAssertEqual(restoredWorkspaces[0].name, "Client Shell")
        XCTAssertEqual(restoredWorkspaces[0].focusedTab?.panes.count, 2)
        XCTAssertEqual(restoredWorkspaces[0].focusedPane?.session.workingDirectory, "/var/tmp")
        XCTAssertNil(restoredWorkspaces[0].focusedPane?.terminalState.statusSummary)
        XCTAssertEqual(restoredActiveWorkspace.id, secondWorkspace.id)
        XCTAssertEqual(restoredController.activeWorkspace()?.id, secondWorkspace.id)
    }

    func testWorkspaceControllerSupportsOrderedWorkspaceSwitchingAndPreviousRecall() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)
        XCTAssertEqual(controller.focusWorkspace(atDisplayIndex: 0)?.id, firstWorkspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.id, firstWorkspace.id)
        XCTAssertEqual(controller.focusPreviousWorkspace()?.id, secondWorkspace.id)
        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)
    }

    func testWorkspaceControllerIgnoresMissingOrderedWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        XCTAssertNil(controller.focusWorkspace(atDisplayIndex: 8))
        XCTAssertEqual(controller.activeWorkspace()?.id, workspace.id)
        XCTAssertFalse(controller.canFocusPreviousWorkspace())
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

        XCTAssertTrue(findLabel(withString: "Workspace 1", in: sidebar))
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

        let wsLabel = try XCTUnwrap(findLabelView(withString: "Workspace 1", in: sidebar))
        let wsButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: wsLabel))
        XCTAssertNotNil(wsButton)
        XCTAssertGreaterThanOrEqual(findViews(ofType: NSImageView.self, in: sidebar).count, 2)
    }

    @MainActor
    func testWorkspaceRowContextMenuIncludesResetOnlyForCustomNames() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.renameWorkspace(workspace.id, to: "Project Alpha")
        let secondWorkspace = try controller.createWorkspace()
        let windowController = WorkspaceWindowController(
            workspace: try XCTUnwrap(controller.activeWorkspace()),
            controller: controller
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        let renamedLabel = try XCTUnwrap(findLabelView(withString: "Project Alpha", in: sidebar))
        let renamedButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: renamedLabel))
        let defaultLabel = try XCTUnwrap(findLabelView(withString: secondWorkspace.name, in: sidebar))
        let defaultButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: defaultLabel))

        let renamedMenuTitles = renamedButton.menu?.items.map(\.title) ?? []
        let defaultMenuTitles = defaultButton.menu?.items.map(\.title) ?? []

        XCTAssertTrue(renamedMenuTitles.contains("Remove Custom Name"))
        XCTAssertFalse(defaultMenuTitles.contains("Remove Custom Name"))
        XCTAssertTrue(renamedMenuTitles.contains("Close Others"))
        XCTAssertTrue(renamedMenuTitles.contains("Close Above"))
        XCTAssertTrue(renamedMenuTitles.contains("Close Below"))
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
    func testWorkspaceWindowUsesUnifiedTitlebarConfiguration() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let renamedWorkspace = try XCTUnwrap(controller.renameWorkspace(workspace.id, to: "Project Alpha"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.title, "Project Alpha")
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

    @MainActor
    func testWorkspaceWindowDoesNotDuplicateFocusedPaneTitleAheadOfTabs() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let paneHeader = try XCTUnwrap(findView(ofType: PaneHeaderView.self, in: rootView))

        XCTAssertEqual(countVisibleNonEmptyLabels(in: paneHeader), 1)
    }

    @MainActor
    func testWorkspaceWindowRestoresPersistedSidebarVisibility() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let store = InMemorySidebarVisibilityStore(isSidebarVisible: false)
        let windowController = WorkspaceWindowController(
            workspace: workspace,
            controller: controller,
            sidebarVisibilityStore: store
        )
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        rootView.layoutSubtreeIfNeeded()

        XCTAssertTrue(sidebar.isHidden)

        windowController.toggleSidebarVisibility()
        XCTAssertTrue(store.isSidebarVisible)
        XCTAssertFalse(sidebar.isHidden)
    }

    func testBuiltInThemesIncludeDefaultAndCuratedPresets() {
        let presets = WorkspaceShellTheme.builtInPresets
        let identifiers = Set(presets.map(\.identifier))

        XCTAssertTrue(identifiers.contains("monokai-soda"))
        XCTAssertTrue(identifiers.contains("catppuccin"))
        XCTAssertTrue(identifiers.contains("dracula"))
        XCTAssertTrue(identifiers.contains("nord"))
        XCTAssertTrue(identifiers.contains("gruvbox"))
        XCTAssertTrue(identifiers.contains("one-dark"))
        XCTAssertTrue(identifiers.contains("solarized-dark"))
        XCTAssertTrue(identifiers.contains("solarized-light"))
        XCTAssertEqual(presets.count, identifiers.count)
        XCTAssertEqual(WorkspaceShellTheme.defaultTheme.identifier, "monokai-soda")
        XCTAssertNotEqual(WorkspaceShellTheme.defaultTheme.terminalPalette, WorkspaceShellTheme.builtInPresets.first(where: { $0.identifier == "catppuccin" })?.terminalPalette)
        XCTAssertTrue(
            presets.allSatisfy {
                $0.shell.windowBackground.isEqual($0.terminalPalette.backgroundColor)
            }
        )
    }

    func testTerminalActionCoordinatorUpdatesPaneStateAndPublishesControlPlaneEvent() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        var publishedEvent: ControlPlaneTerminalEvent?
        controller.onTerminalEvent = { event in
            publishedEvent = event
        }

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: runtimeSurfaceID)

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.session.workingDirectory, "/var/tmp")
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.terminalState.reportedWorkingDirectory, "/var/tmp")
        XCTAssertEqual(publishedEvent?.name, .workingDirectoryChanged)
        XCTAssertEqual(publishedEvent?.payload.objectValue?["path"], .string("/var/tmp"))
    }

    @MainActor
    func testWorkspaceWindowShowsPaneStatusForTerminalProgressEvents() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        runtime.emit(.progressReported(state: .active, progress: 42), on: runtimeSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        XCTAssertTrue(findLabel(withString: "Progress 42%", in: rootView))
    }

    @MainActor
    func testWorkspaceWindowSuppressesCwdOnlyPaneStatusRow() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let paneCard = try XCTUnwrap(findView(ofType: PaneCardView.self, in: rootView))

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: runtimeSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        XCTAssertFalse(findLabel(withString: "/var/tmp", in: paneCard))
    }

    @MainActor
    func testWorkspaceWindowShowsTerminalMetadataRowsAndNavigatesViaSidebar() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPane = try XCTUnwrap(workspace.focusedPane)
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let secondPane = try XCTUnwrap(updatedWorkspace.focusedPane)
        let secondSurfaceID = try XCTUnwrap(bridge.surface(for: secondPane.id)?.runtimeSurfaceID)
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: secondSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        XCTAssertTrue(findLabel(withString: "/tmp", in: sidebar))
        let secondPathLabel = try XCTUnwrap(findLabelView(withString: "/var/tmp", in: sidebar))
        let secondPathButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: secondPathLabel))
        secondPathButton.mouseDown(with: makeMouseEvent(window: window))

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.id, secondPane.id)
        XCTAssertNotEqual(firstPane.id, secondPane.id)
    }

    @MainActor
    func testPaneTabContextMenuExposesRenameAndCloseVariants() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let windowController = WorkspaceWindowController(workspace: updatedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        let tabButtons = findViews(ofType: NSControl.self, in: rootView).filter { $0.menu != nil }
        XCTAssertEqual(tabButtons.count, 2)
        let menuTitles = tabButtons[0].menu?.items.map(\.title) ?? []

        XCTAssertTrue(menuTitles.contains("Rename…"))
        XCTAssertTrue(menuTitles.contains("Close"))
        XCTAssertTrue(menuTitles.contains("Close Others"))
        XCTAssertTrue(menuTitles.contains("Close Above"))
        XCTAssertTrue(menuTitles.contains("Close Below"))
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    @MainActor
    func testSidebarTerminalRowContextMenuExposesRenameAndCloseVariants() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab())
        let secondPane = try XCTUnwrap(updatedWorkspace.focusedPane)
        let renamedWorkspace = try XCTUnwrap(controller.renamePaneTab(secondPane.id, to: "hx"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        let terminalLabel = try XCTUnwrap(findLabelView(withString: "hx", in: sidebar))
        let terminalButton = try XCTUnwrap(findAncestor(ofType: SidebarItemButton.self, for: terminalLabel))
        let menuTitles = terminalButton.menu?.items.map(\.title) ?? []

        XCTAssertTrue(menuTitles.contains("Rename…"))
        XCTAssertTrue(menuTitles.contains("Close"))
        XCTAssertTrue(menuTitles.contains("Close Others"))
        XCTAssertTrue(menuTitles.contains("Close Above"))
        XCTAssertTrue(menuTitles.contains("Close Below"))
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    @MainActor
    func testWorkspaceWindowShowsGitAwareTerminalMetadataWhenRepositoryIsAvailable() throws {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", repositoryURL.path])
        try runGit(["-C", repositoryURL.path, "branch", "-M", "main"])

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: repositoryURL.path)
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))
        let expectedTitle = "main"

        XCTAssertTrue(findLabel(withString: expectedTitle, in: sidebar))
        XCTAssertTrue(findLabel(withString: repositoryURL.path, in: sidebar))
    }

    @MainActor
    func testWorkspaceWindowPrefersPaneTitleInTerminalMetadataRows() throws {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", repositoryURL.path])
        try runGit(["-C", repositoryURL.path, "branch", "-M", "main"])

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: repositoryURL.path)
        let paneID = try XCTUnwrap(workspace.focusedPane?.id)
        let renamedWorkspace = try XCTUnwrap(controller.renamePaneTab(paneID, to: "hx"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        XCTAssertTrue(findLabel(withString: "hx", in: sidebar))
        XCTAssertTrue(findLabel(withString: "main · \(repositoryURL.path)", in: sidebar))
    }

    @MainActor
    func testWorkspaceWindowKeepsSinglePaneFilledAcrossCanvas() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        windowController.showWindow(nil)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))
        let canvas = try XCTUnwrap(findView(ofType: WorkspaceCanvasView.self, in: rootView))
        let hostedPane = try XCTUnwrap(findView(ofType: HostedTerminalPaneView.self, in: rootView))

        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let sidebarFrame = sidebar.convert(sidebar.bounds, to: rootView)
        let canvasFrame = canvas.convert(canvas.bounds, to: rootView)
        let hostedFrame = hostedPane.convert(hostedPane.bounds, to: rootView)

        XCTAssertEqual(canvasFrame.minX, sidebarFrame.maxX, accuracy: 1)
        XCTAssertEqual(canvasFrame.maxX, rootView.bounds.maxX, accuracy: 1)
        XCTAssertEqual(hostedFrame.minX, canvasFrame.minX, accuracy: 1)
        XCTAssertEqual(hostedFrame.maxX, canvasFrame.maxX, accuracy: 1)
    }

    func testTerminalActionCoordinatorEmitsStructuredHooksAndNativeNotifications() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .command,
                name: "terminal-command-finished",
                executableURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
        let runner = ExternalHookRunner(
            registry: registry,
            launcher: launcher
        )
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: runner
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        runtime.emit(.commandFinished(exitCode: 0, durationNanoseconds: 123), on: runtimeSurfaceID)

        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.name, "terminal-command-finished")
        XCTAssertEqual(invocation.payload.objectValue?["exitCode"], .integer(0))
        XCTAssertEqual(controller.latestNotification()?.title, "Command finished")
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
    private func countVisibleNonEmptyLabels(in view: NSView) -> Int {
        let ownCount: Int
        if let label = view as? NSTextField, !label.isHidden, !label.stringValue.isEmpty {
            ownCount = 1
        } else {
            ownCount = 0
        }

        return ownCount + view.subviews.reduce(0) { $0 + countVisibleNonEmptyLabels(in: $1) }
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

    @MainActor
    private func makeMouseEvent(window: NSWindow) -> NSEvent {
        try! XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 12, y: 12),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private final class ActionEmittingGhosttyRuntime: GhosttyRuntime {
    private var sessions: [String: SessionDescriptor] = [:]
    private var terminalActionHandler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?

    func createSurface(for paneID: PaneID) throws -> String {
        "action:\(paneID.rawValue)"
    }

    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        sessions[runtimeSurfaceID] = session
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        sessions.removeValue(forKey: runtimeSurfaceID)
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return nil
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        sessions[runtimeSurfaceID] != nil
    }

    func setTerminalActionHandler(
        _ handler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    ) {
        terminalActionHandler = handler
    }

    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        fallbackSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        guard sessions[runtimeSurfaceID] != nil else {
            return nil
        }

        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: runtimeSurfaceID,
            transcript: "",
            currentInput: "",
            shell: descriptor.shell,
            workingDirectory: descriptor.workingDirectory,
            columns: fallbackSize.columns,
            rows: fallbackSize.rows
        )
    }

    func emit(_ action: TerminalAction, on runtimeSurfaceID: String) {
        _ = terminalActionHandler?(RuntimeTerminalActionRecord(runtimeSurfaceID: runtimeSurfaceID, action: action))
    }
}

private final class CapturingHookLauncher: HookProcessLaunching {
    private(set) var invocations: [HookInvocation] = []

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = executableURL
        _ = arguments
        _ = environment
        invocations.append(try JSONDecoder().decode(HookInvocation.self, from: input))
    }
}
