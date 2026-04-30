import AppKit
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
}
