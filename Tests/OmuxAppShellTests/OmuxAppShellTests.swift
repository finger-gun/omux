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

    func testRunCommandTargetsLiveSession() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "printf 'hello'"))
    }
}
