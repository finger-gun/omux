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

    private func requestControlMethod(_ method: ControlMethod, socketPath: String) throws -> JSONRPCResponse {
        let requestFinished = expectation(description: "control-plane \(method.rawValue) request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketPath)
                responseBox.value = try client.request(method: method, params: nil)
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        if let error = errorBox.value {
            throw error
        }
        return try XCTUnwrap(responseBox.value)
    }

    private func targetPaneID(in response: JSONRPCResponse) -> PaneID? {
        guard case .object(let object)? = response.result,
              case .object(let target)? = object["target"],
              case .string(let paneID)? = target["paneID"]
        else {
            return nil
        }

        return PaneID(rawValue: paneID)
    }

    func testWorkspaceControllerCreatesTabsAndSplits() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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

    func testWorkspaceControllerUsesConfiguredDefaultRootForNewWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner(),
            defaultWorkspaceRootPath: "/tmp"
        )

        let workspace = try controller.createWorkspace()

        XCTAssertEqual(workspace.rootPath, "/tmp")
    }

    func testWorkspaceControllerCanSplitDown() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let withVerticalSplit = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))

        XCTAssertEqual(withVerticalSplit.focusedTab?.panes.count, 2)
    }

    func testWorkspaceControllerSupportsNestedSplitLayouts() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitDown = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let bottomPaneID = try XCTUnwrap(splitDown.focusedTab?.focusedPaneID)

        _ = controller.focus(paneID: bottomPaneID)
        let nestedLayout = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))

        XCTAssertEqual(nestedLayout.focusedTab?.panes.count, 3)

        guard case .split(axis: .rows, proportions: _, children: let rootChildren)? = nestedLayout.focusedTab?.rootLayout else {
            return XCTFail("expected a row split at the root")
        }

        XCTAssertEqual(rootChildren.count, 2)
        guard case .split(axis: .columns, proportions: _, children: let nestedChildren) = rootChildren[1] else {
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

    func testWorkspaceControllerCyclesPanesInVisibleLayoutOrder() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let secondPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        XCTAssertEqual(splitWorkspace.focusedTab?.visiblePaneIDs, [firstPaneID, secondPaneID])

        let next = try XCTUnwrap(controller.focusNextPane())
        XCTAssertEqual(next.focusedPane?.id, firstPaneID)

        let previous = try XCTUnwrap(controller.focusPreviousPane())
        XCTAssertEqual(previous.focusedPane?.id, secondPaneID)
    }

    @MainActor
    func testWorkspaceAutomationCanChainSplitFocusAndRunByReturnedIDs() throws {
        let bridge = GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime())
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let lower = try XCTUnwrap(controller.splitPane(target: .workspace(workspace.id), axis: .rows))
        let lowerLeft = try XCTUnwrap(controller.splitPane(target: .pane(lower.created.paneID), axis: .columns))

        let expectation = expectation(description: "targeted command executes in selected pane")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: lowerLeft.created.paneID) { snapshot in
            if snapshot.renderedText.contains("automation-dev\n") {
                expectation.fulfill()
            }
        }

        let runResult = try XCTUnwrap(controller.runCommand(
            target: .pane(lowerLeft.created.paneID),
            command: "printf 'automation-dev' && printf '\\n'"
        ))

        XCTAssertEqual(runResult.target?.paneID, lowerLeft.created.paneID)
        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: lowerLeft.created.paneID, token: token)
    }

    func testWorkspaceControllerCreatesAndClosesPaneTabsInFocusedStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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

    func testWorkspaceControllerCyclesPaneTabsInFocusedStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var focusEvents = [ControlPlaneEvent]()
        controller.onControlPlaneEvent = { event in
            if event.name == ControlPlaneActionEventName.paneTabFocused.rawValue {
                focusEvents.append(event)
            }
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let withPaneTab = try XCTUnwrap(controller.createPaneTab())
        let secondPaneID = try XCTUnwrap(withPaneTab.focusedPane?.id)

        let next = try XCTUnwrap(controller.focusNextPaneTab())
        XCTAssertEqual(next.focusedPane?.id, firstPaneID)

        let previous = try XCTUnwrap(controller.focusPreviousPaneTab())
        XCTAssertEqual(previous.focusedPane?.id, secondPaneID)
        XCTAssertEqual(focusEvents.map(\.paneID), [firstPaneID, secondPaneID])
        XCTAssertNil(controller.focusNextPane())
    }

    func testWorkspaceControllerKeepsSinglePaneTabNavigationInert() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var focusEventCount = 0
        controller.onControlPlaneEvent = { event in
            if event.name == ControlPlaneActionEventName.paneTabFocused.rawValue {
                focusEventCount += 1
            }
        }

        _ = try controller.openWorkspace(at: "/tmp")

        XCTAssertNil(controller.focusNextPaneTab())
        XCTAssertNil(controller.focusPreviousPaneTab())
        XCTAssertNil(controller.focusNextPane())
        XCTAssertNil(controller.focusPreviousPane())
        XCTAssertEqual(focusEventCount, 0)
    }

    func testWorkspaceControllerCreatesPaneTabInExplicitStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let targetStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: splitPaneID)?.id)
        let originalStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: originalPaneID)?.id)

        _ = try XCTUnwrap(controller.focus(paneID: originalPaneID))
        let updatedWorkspace = try XCTUnwrap(controller.createPaneTab(in: targetStackID))
        let originalStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: originalStackID))
        let targetStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: targetStackID))

        XCTAssertEqual(originalStack.panes.map(\.id), [originalPaneID])
        XCTAssertEqual(targetStack.panes.count, 2)
        XCTAssertEqual(updatedWorkspace.focusedPane?.id, targetStack.focusedPaneID)
        XCTAssertNotEqual(updatedWorkspace.focusedPane?.id, originalPaneID)
    }

    func testPaneCreationInheritsLatestKnownWorkingDirectory() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let originalPane = try XCTUnwrap(workspace.focusedPane)
        let originalSurfaceID = try XCTUnwrap(bridge.surface(for: originalPane.id)?.runtimeSurfaceID)
        runtime.emit(.workingDirectoryChanged("/tmp/project/packages/api"), on: originalSurfaceID)

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let splitPane = try XCTUnwrap(splitWorkspace.focusedPane)
        XCTAssertEqual(splitPane.session.workingDirectory, "/tmp/project/packages/api")

        let splitSurfaceID = try XCTUnwrap(bridge.surface(for: splitPane.id)?.runtimeSurfaceID)
        runtime.emit(.workingDirectoryChanged("/tmp/project/packages/web"), on: splitSurfaceID)
        let paneTabWorkspace = try XCTUnwrap(controller.createPaneTab())

        XCTAssertEqual(paneTabWorkspace.focusedPane?.session.workingDirectory, "/tmp/project/packages/web")
    }

    func testNewPanesDoNotInheritTerminalReportedTitleFromFocusedPane() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/omux")
        let originalPane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: originalPane.id)?.runtimeSurfaceID)

        runtime.emit(.titleChanged("GitHub Copilot"), on: runtimeSurfaceID)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.title, "GitHub Copilot")

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        XCTAssertEqual(splitWorkspace.focusedPane?.title, "omux")

        let paneTabWorkspace = try XCTUnwrap(controller.createPaneTab())
        XCTAssertEqual(paneTabWorkspace.focusedPane?.title, "omux")
    }

    func testTerminalHistoryResolvesActivePaneAndAllWorkspaceScopes() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp/omux")
        let firstPane = try XCTUnwrap(firstWorkspace.focusedPane)
        let firstSurfaceID = try XCTUnwrap(bridge.surface(for: firstPane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[firstSurfaceID] = "omux-one\nomux-two"

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let splitPane = try XCTUnwrap(splitWorkspace.focusedPane)
        let splitSurfaceID = try XCTUnwrap(bridge.surface(for: splitPane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[splitSurfaceID] = "split-history"

        let secondWorkspace = try controller.openWorkspace(at: "/tmp/dungeon")
        let secondPane = try XCTUnwrap(secondWorkspace.focusedPane)
        let secondSurfaceID = try XCTUnwrap(bridge.surface(for: secondPane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[secondSurfaceID] = "dungeon-history"

        let activeHistory = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest()))
        XCTAssertEqual(activeHistory.items.map(\.workspaceID), [secondWorkspace.id])
        XCTAssertEqual(activeHistory.items.map(\.paneID), [secondPane.id])
        XCTAssertEqual(activeHistory.items.first?.text, "dungeon-history")

        let paneHistory = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(
            scope: .pane(firstPane.id),
            maxBytes: 1_000,
            maxLines: 1
        )))
        XCTAssertEqual(paneHistory.items.map(\.paneID), [firstPane.id])
        XCTAssertEqual(paneHistory.items.first?.text, "omux-two")
        XCTAssertEqual(paneHistory.items.first?.lineCount, 1)
        XCTAssertTrue(paneHistory.items.first?.truncated == true)

        let allHistory = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .all)))
        XCTAssertEqual(Set(allHistory.items.map(\.paneID)), Set([firstPane.id, splitPane.id, secondPane.id]))
        XCTAssertNil(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .pane(PaneID(rawValue: "missing")))))
    }

    func testTerminalHistoryReportsUnavailableAndDoesNotMutatePersistenceOrInput() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/empty")
        let pane = try XCTUnwrap(workspace.focusedPane)

        let history = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .pane(pane.id))))
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.text, "")
        XCTAssertEqual(history.items.first?.unavailable, "history unavailable")
        XCTAssertEqual(runtime.sentTextCount, 0)

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let persistedPane = try XCTUnwrap(snapshot.workspaces.first?.tabs.first?.panes.first)
        XCTAssertNil(persistedPane.terminalState.restoredScrollback)
    }

    func testWorkspaceControllerPublishesSharedActionEvents() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalSessionID = try XCTUnwrap(workspace.focusedPane?.session.id)

        _ = try XCTUnwrap(controller.createTab())
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let splitSessionID = try XCTUnwrap(splitWorkspace.focusedPane?.session.id)
        let paneTabWorkspace = try XCTUnwrap(controller.createPaneTab())
        let paneTabID = try XCTUnwrap(paneTabWorkspace.focusedPane?.id)
        _ = try XCTUnwrap(controller.focusPaneTab(paneID: splitPaneID))
        _ = try XCTUnwrap(controller.closePaneTab(paneID: paneTabID))
        XCTAssertTrue(try controller.focus(sessionID: originalSessionID))
        XCTAssertTrue(try controller.runCommand(in: splitSessionID, command: "pwd"))

        XCTAssertEqual(
            publishedEvents.map(\.name),
            [
                "workspace.opened",
                "tab.created",
                "pane.split",
                "paneTab.created",
                "paneTab.focused",
                "paneTab.closed",
                "session.focused",
                "command.started",
            ]
        )
        XCTAssertEqual(publishedEvents[0].payload.objectValue?["path"], .string("/tmp"))
        XCTAssertEqual(publishedEvents[2].payload.objectValue?["axis"], .string("rows"))
        XCTAssertNotNil(publishedEvents[3].payload.objectValue?["paneStackID"])
        XCTAssertEqual(publishedEvents[4].paneID, splitPaneID)
    }

    func testWorkspaceControllerPublishesSparseNotificationAndRestoreEvents() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.openWorkspace(at: "/var/tmp")

        publishedEvents.removeAll()
        try controller.notify(NotificationRequest(title: "Done", body: "Build finished"))
        let restoredWorkspace = try XCTUnwrap(controller.restore(workspaceID: firstWorkspace.id))

        XCTAssertEqual(restoredWorkspace.id, firstWorkspace.id)
        XCTAssertEqual(publishedEvents.map(\.name), ["notification.raised", "workspace.restored"])
        XCTAssertEqual(publishedEvents[0].workspaceID, secondWorkspace.id)
        XCTAssertNil(publishedEvents[0].paneID)
        XCTAssertNil(publishedEvents[0].sessionID)
        XCTAssertEqual(publishedEvents[1].workspaceID, firstWorkspace.id)
        XCTAssertNil(publishedEvents[1].paneID)
    }

    func testWorkspaceControllerDoesNotPublishActionEventsForRejectedActions() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        var publishedEvents: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            publishedEvents.append(event)
        }

        _ = try controller.openWorkspace(at: "/tmp")
        publishedEvents.removeAll()

        XCTAssertFalse(try controller.focus(sessionID: SessionID(rawValue: "missing-session")))
        XCTAssertFalse(try controller.runCommand(in: SessionID(rawValue: "missing-session"), command: "pwd"))
        XCTAssertNil(try controller.closePaneTab(paneID: PaneID(rawValue: "missing-pane")))
        XCTAssertNil(controller.restore(workspaceID: WorkspaceID(rawValue: "missing-workspace")))
        XCTAssertTrue(publishedEvents.isEmpty)
    }

    func testWorkspaceControllerRemovesActivePaneByClosingSinglePaneTab() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertEqual(firstWorkspace.name, "Workspace 1")
        XCTAssertEqual(secondWorkspace.name, "Workspace 2")
    }

    func testWorkspaceControllerReusesLowestAvailableGeneratedWorkspaceName() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let renamedWorkspace = try XCTUnwrap(controller.renameWorkspace(workspace.id, to: "Project Alpha"))

        XCTAssertEqual(renamedWorkspace.name, "Project Alpha")
        XCTAssertEqual(controller.activeWorkspace()?.name, "Project Alpha")
    }

    func testWorkspaceControllerCanRemoveCustomWorkspaceName() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
        _ = controller.updateSplitProportions(
            [0.7, 0.3],
            forChildPaneIDs: [
                firstPane.id,
                try XCTUnwrap(splitWorkspace.focusedPane?.id),
            ]
        )
        let secondWorkspace = try controller.createWorkspace()
        _ = controller.focus(paneID: try XCTUnwrap(splitWorkspace.focusedPane?.id))

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let restoredController = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let restoredActiveWorkspace = try XCTUnwrap(restoredController.restorePersistedState(snapshot))
        let restoredWorkspaces = restoredController.allWorkspaces()

        XCTAssertEqual(restoredWorkspaces.count, 2)
        XCTAssertEqual(restoredWorkspaces[0].name, "Client Shell")
        XCTAssertEqual(restoredWorkspaces[0].focusedTab?.panes.count, 2)
        XCTAssertEqual(restoredWorkspaces[0].focusedPane?.session.workingDirectory, "/var/tmp")
        XCTAssertNil(restoredWorkspaces[0].focusedPane?.terminalState.statusSummary)
        guard case .split(axis: .columns, proportions: let restoredProportions, children: _)? = restoredWorkspaces[0].focusedTab?.rootLayout else {
            return XCTFail("expected restored layout to keep split proportions")
        }
        XCTAssertEqual(restoredProportions.count, 2)
        XCTAssertEqual(restoredProportions[0], 0.7, accuracy: 0.0001)
        XCTAssertEqual(restoredProportions[1], 0.3, accuracy: 0.0001)
        XCTAssertEqual(restoredActiveWorkspace.id, secondWorkspace.id)
        XCTAssertEqual(restoredController.activeWorkspace()?.id, secondWorkspace.id)
    }

    func testWorkspaceControllerPersistsDistinctPaneWorkingDirectoriesAcrossWorkspaces() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let omuxWorkspace = try controller.openWorkspace(at: "/Users/example/projects/omux")
        let omuxPane = try XCTUnwrap(omuxWorkspace.focusedPane)
        runtime.emit(
            .workingDirectoryChanged("/Users/example/projects/omux/Sources"),
            on: try XCTUnwrap(bridge.surface(for: omuxPane.id)?.runtimeSurfaceID)
        )

        let dungeonWorkspace = try controller.createWorkspace()
        let dungeonPane = try XCTUnwrap(dungeonWorkspace.focusedPane)
        runtime.emit(
            .workingDirectoryChanged("/Users/example/projects/DungeonPlanner"),
            on: try XCTUnwrap(bridge.surface(for: dungeonPane.id)?.runtimeSurfaceID)
        )
        let dungeonSplit = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let dungeonSplitPane = try XCTUnwrap(dungeonSplit.focusedPane)
        runtime.emit(
            .workingDirectoryChanged("/Users/example/projects/DungeonPlanner/App"),
            on: try XCTUnwrap(bridge.surface(for: dungeonSplitPane.id)?.runtimeSurfaceID)
        )

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let restoredController = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )
        _ = try XCTUnwrap(restoredController.restorePersistedState(snapshot))

        let restoredDirectories = restoredController.allWorkspaces()
            .flatMap(\.tabs)
            .flatMap(\.panes)
            .map(\.session.workingDirectory)

        XCTAssertTrue(restoredDirectories.contains("/Users/example/projects/omux/Sources"))
        XCTAssertTrue(restoredDirectories.contains("/Users/example/projects/DungeonPlanner"))
        XCTAssertTrue(restoredDirectories.contains("/Users/example/projects/DungeonPlanner/App"))
    }

    func testWorkspacePersistenceStoresBoundedPaneScrollbackForHistoryCommand() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp/project")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = (1...500).map { "line-\($0)" }.joined(separator: "\n")

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let persistedPane = try XCTUnwrap(snapshot.workspaces.first?.focusedPane)

        XCTAssertEqual(persistedPane.terminalState.restoredScrollback?.text.split(separator: "\n").count, 400)
        XCTAssertEqual(persistedPane.terminalState.restoredScrollback?.text.split(separator: "\n").first, "line-101")
        XCTAssertEqual(persistedPane.terminalState.restoredScrollback?.text.split(separator: "\n").last, "line-500")
        XCTAssertTrue(persistedPane.terminalState.restoredScrollback?.truncated == true)
    }

    func testWorkspaceRestoreKeepsSavedScrollbackForHistoryCommandWithoutRenderingIt() throws {
        let scrollback = PaneScrollbackSnapshot(text: "previous output", truncated: false)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let pane = Pane(
            title: "project",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: scrollback)
        )
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(generatedName: "Workspace 1", rootPath: "/tmp/project", tabs: [tab], focusedTabID: tab.id)
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try XCTUnwrap(controller.restorePersistedState(.init(workspaces: [workspace], activeWorkspaceID: workspace.id)))

        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.terminalState.restoredScrollback, scrollback)
        XCTAssertEqual(controller.activeWorkspace()?.focusedPane?.session.workingDirectory, "/tmp/project")

        let history = try XCTUnwrap(controller.terminalHistory(ControlPlaneHistoryRequest(scope: .pane(pane.id))))
        XCTAssertEqual(history.items.first?.text, "previous output")
    }

    func testWorkspaceControllerSupportsOrderedWorkspaceSwitchingAndPreviousRecall() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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

    func testWorkspaceControllerMovesActiveWorkspaceUpAndDown() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        let thirdWorkspace = try controller.createWorkspace()

        XCTAssertEqual(controller.listWorkspaces().map(\.id), [firstWorkspace.id, secondWorkspace.id, thirdWorkspace.id])
        XCTAssertEqual(controller.activeWorkspace()?.id, thirdWorkspace.id)
        XCTAssertTrue(controller.canMoveActiveWorkspaceUp())
        XCTAssertFalse(controller.canMoveActiveWorkspaceDown())

        let movedUp = try XCTUnwrap(controller.moveActiveWorkspaceUp())
        XCTAssertEqual(movedUp.id, thirdWorkspace.id)
        XCTAssertEqual(controller.listWorkspaces().map(\.id), [firstWorkspace.id, thirdWorkspace.id, secondWorkspace.id])
        XCTAssertTrue(controller.canMoveActiveWorkspaceUp())
        XCTAssertTrue(controller.canMoveActiveWorkspaceDown())

        let movedDown = try XCTUnwrap(controller.moveActiveWorkspaceDown())
        XCTAssertEqual(movedDown.id, thirdWorkspace.id)
        XCTAssertEqual(controller.listWorkspaces().map(\.id), [firstWorkspace.id, secondWorkspace.id, thirdWorkspace.id])
        XCTAssertFalse(controller.canMoveActiveWorkspaceDown())
    }

    func testWorkspaceControllerDoesNotMoveActiveWorkspacePastBounds() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertNil(controller.moveActiveWorkspaceDown())
        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)

        _ = controller.moveActiveWorkspaceUp()
        XCTAssertNil(controller.moveActiveWorkspaceUp())
        XCTAssertFalse(controller.canMoveActiveWorkspaceUp())
        XCTAssertTrue(controller.canMoveActiveWorkspaceDown())
    }

    func testWorkspaceControllerPersistsReorderedWorkspaceOrder() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let secondWorkspace = try controller.createWorkspace()
        let thirdWorkspace = try controller.createWorkspace()

        _ = controller.moveWorkspace(thirdWorkspace.id, toDisplayIndex: 0)
        XCTAssertEqual(controller.listWorkspaces().map(\.id), [thirdWorkspace.id, firstWorkspace.id, secondWorkspace.id])

        let snapshot = try XCTUnwrap(controller.persistenceSnapshot())
        let restoredController = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        _ = try XCTUnwrap(restoredController.restorePersistedState(snapshot))
        XCTAssertEqual(restoredController.listWorkspaces().map(\.id), [thirdWorkspace.id, firstWorkspace.id, secondWorkspace.id])
        XCTAssertEqual(restoredController.activeWorkspace()?.id, thirdWorkspace.id)
    }

    func testWorkspaceControllerIgnoresMissingOrderedWorkspace() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        XCTAssertNil(controller.focusWorkspace(atDisplayIndex: 8))
        XCTAssertEqual(controller.activeWorkspace()?.id, workspace.id)
        XCTAssertFalse(controller.canFocusPreviousWorkspace())
    }

    func testRunCommandTargetsLiveSession() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let sessionID = try XCTUnwrap(workspace.focusedPane?.session.id)
        XCTAssertTrue(try controller.runCommand(in: sessionID, command: "printf 'hello'"))
    }

    @MainActor
    func testRunCommandPreservesSessionContinuity() throws {
        let bridge = GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime())
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
    func testWorkspaceWindowReflectsReorderedWorkspaceSidebarOrder() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        _ = try controller.renameWorkspace(firstWorkspace.id, to: "Alpha")
        let secondWorkspace = try controller.createWorkspace()
        _ = try controller.renameWorkspace(secondWorkspace.id, to: "Beta")
        let thirdWorkspace = try controller.createWorkspace()
        let reorderedWorkspace = try XCTUnwrap(controller.renameWorkspace(thirdWorkspace.id, to: "Gamma"))

        let windowController = WorkspaceWindowController(workspace: reorderedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        let sidebar = try XCTUnwrap(findView(ofType: WorkspaceSidebarView.self, in: rootView))

        _ = controller.moveWorkspace(thirdWorkspace.id, toDisplayIndex: 0)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        window.contentView?.layoutSubtreeIfNeeded()
        rootView.layoutSubtreeIfNeeded()

        let alphaLabel = try XCTUnwrap(findLabelView(withString: "Alpha", in: sidebar))
        let gammaLabel = try XCTUnwrap(findLabelView(withString: "Gamma", in: sidebar))
        let betaLabel = try XCTUnwrap(findLabelView(withString: "Beta", in: sidebar))

        let gammaFrame = gammaLabel.convert(gammaLabel.bounds, to: rootView)
        let alphaFrame = alphaLabel.convert(alphaLabel.bounds, to: rootView)
        let betaFrame = betaLabel.convert(betaLabel.bounds, to: rootView)

        XCTAssertGreaterThan(gammaFrame.minY, alphaFrame.minY)
        XCTAssertGreaterThan(alphaFrame.minY, betaFrame.minY)
    }

    @MainActor
    func testWorkspaceWindowUsesUnifiedTitlebarConfiguration() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let renamedWorkspace = try XCTUnwrap(controller.renameWorkspace(workspace.id, to: "Project Alpha"))
        let windowController = WorkspaceWindowController(workspace: renamedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.title, "Project Alpha")
        XCTAssertTrue(window.contentViewController?.view is WorkspaceRootView)
    }

    @MainActor
    func testWorkspaceRootViewDoubleClickInUnifiedTitlebarRequestsZoom() throws {
        let rootView = WorkspaceRootView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        rootView.titlebarHeightOverrideForTesting = 36
        let window = NSWindow(
            contentRect: rootView.bounds,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        var zoomRequested = false
        rootView.titlebarDoubleClickHandler = { _ in
            zoomRequested = true
        }

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 80, y: 470),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 2,
                pressure: 1
            )
        )

        rootView.mouseDown(with: event)

        XCTAssertTrue(zoomRequested)
    }

    @MainActor
    func testWorkspaceWindowRendersHorizontalSplitForSplitRight() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
    func testSplitDividerDoesNotOptIntoWindowBackgroundDragging() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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

        let splitLayoutView = try XCTUnwrap(findView(ofType: SplitLayoutView.self, in: rootView))
        XCTAssertFalse(splitLayoutView.mouseDownCanMoveWindow)
    }

    @MainActor
    func testWorkspaceWindowUsesDedicatedPaneHeaderChrome() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let windowController = WorkspaceWindowController(workspace: workspace, controller: controller)
        let rootView = try XCTUnwrap(windowController.window?.contentViewController?.view)

        XCTAssertNotNil(findView(ofType: PaneHeaderView.self, in: rootView))
        XCTAssertNil(findView(ofType: NSSegmentedControl.self, in: rootView))
    }

    @MainActor
    func testWorkspaceWindowPreservesFocusedPaneResponderAcrossTerminalStateUpdates() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        _ = try controller.openWorkspace(at: "/tmp")
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane())
        let secondPane = try XCTUnwrap(splitWorkspace.focusedPane)
        let secondSurfaceID = try XCTUnwrap(bridge.surface(for: secondPane.id)?.runtimeSurfaceID)

        let windowController = WorkspaceWindowController(workspace: splitWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)
        rootView.layoutSubtreeIfNeeded()

        var paneViews = findViews(ofType: HostedTerminalPaneView.self, in: rootView)
        XCTAssertEqual(paneViews.count, 2)
        let secondPaneView = try XCTUnwrap(paneViews.last)
        window.makeFirstResponder(secondPaneView.focusTarget)

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: secondSurfaceID)
        windowController.update(workspace: try XCTUnwrap(controller.activeWorkspace()))
        rootView.layoutSubtreeIfNeeded()

        paneViews = findViews(ofType: HostedTerminalPaneView.self, in: rootView)
        XCTAssertEqual(paneViews.count, 2)
        XCTAssertTrue(window.firstResponder === paneViews.last?.focusTarget)
    }

    @MainActor
    func testWorkspaceWindowIgnoresInactiveWorkspaceUpdatesForDisplay() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        let firstWorkspace = try controller.openWorkspace(at: "/tmp")
        let firstPane = try XCTUnwrap(firstWorkspace.focusedPane)
        let firstSurfaceID = try XCTUnwrap(bridge.surface(for: firstPane.id)?.runtimeSurfaceID)
        let secondWorkspace = try controller.createWorkspace()

        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)

        let windowController = WorkspaceWindowController(workspace: secondWorkspace, controller: controller)
        XCTAssertEqual(windowController.window?.title, secondWorkspace.name)

        runtime.emit(.progressReported(state: .active, progress: 42), on: firstSurfaceID)
        windowController.update(workspace: firstWorkspace)

        XCTAssertEqual(controller.activeWorkspace()?.id, secondWorkspace.id)
        XCTAssertEqual(windowController.window?.title, secondWorkspace.name)
    }

    @MainActor
    func testWorkspaceWindowDoesNotDuplicateFocusedPaneTitleAheadOfTabs() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
        XCTAssertEqual(publishedEvent?.name, "terminal.cwdChanged")
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
    func testPaneTabAddButtonCreatesTabInClickedPaneStack() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner()
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let originalPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let targetStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: splitPaneID)?.id)
        let originalStackID = try XCTUnwrap(splitWorkspace.focusedTab?.rootLayout.paneStack(containingPaneID: originalPaneID)?.id)
        let refocusedWorkspace = try XCTUnwrap(controller.focus(paneID: originalPaneID))
        let windowController = WorkspaceWindowController(workspace: refocusedWorkspace, controller: controller)
        let window = try XCTUnwrap(windowController.window)
        let rootView = try XCTUnwrap(window.contentViewController?.view)

        let addButton = try XCTUnwrap(
            findViews(ofType: NSControl.self, in: rootView)
                .first { $0.identifier?.rawValue == "pane-tab-add-\(targetStackID.rawValue)" }
        )

        addButton.mouseDown(with: makeMouseEvent(window: window))

        let updatedWorkspace = try XCTUnwrap(controller.activeWorkspace())
        let originalStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: originalStackID))
        let targetStack = try XCTUnwrap(updatedWorkspace.focusedTab?.rootLayout.paneStack(id: targetStackID))
        XCTAssertEqual(originalStack.panes.map(\.id), [originalPaneID])
        XCTAssertEqual(targetStack.panes.count, 2)
        XCTAssertEqual(updatedWorkspace.focusedPane?.id, targetStack.focusedPaneID)
    }

    @MainActor
    func testPaneTabContextMenuExposesRenameAndCloseVariants() throws {
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
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

    func testCommandFailureHookReceivesCommandContextAndOutputState() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        runtime.transcript = "runtime output tail"
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        for hookName in ["command-started", "terminal-command-finished", "command-failed"] {
            registry.register(
                HookDescriptor(
                    category: .command,
                    name: hookName,
                    executableURL: URL(fileURLWithPath: "/usr/bin/true")
                )
            )
        }
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        _ = try controller.runCommand(target: .session(pane.session.id), command: "pnpm test")
        runtime.emit(.commandFinished(exitCode: 1, durationNanoseconds: 456), on: runtimeSurfaceID)

        XCTAssertEqual(launcher.invocations.map(\.name), [
            "command-started",
            "terminal-command-finished",
            "command-failed",
        ])
        let failed = try XCTUnwrap(launcher.invocations.last)
        XCTAssertEqual(failed.workspaceID, workspace.id)
        XCTAssertEqual(failed.paneID, pane.id)
        XCTAssertEqual(failed.sessionID, pane.session.id)
        XCTAssertEqual(failed.payload.objectValue?["command"], .string("pnpm test"))
        XCTAssertEqual(failed.payload.objectValue?["cwd"], .string("/tmp"))
        XCTAssertEqual(failed.payload.objectValue?["exitCode"], .integer(1))
        XCTAssertEqual(failed.payload.objectValue?["durationNanoseconds"], .integer(456))
        XCTAssertEqual(failed.payload.objectValue?["outputContext"]?.objectValue?["kind"], .string("tail"))
        XCTAssertEqual(launcher.invocations[0].payload.objectValue?["outputContext"]?.objectValue?["kind"], .string("unavailable"))
    }

    func testSuccessfulCommandCompletionDoesNotEmitCommandFailedHook() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let launcher = CapturingHookLauncher()
        let registry = HookRegistry()
        for hookName in ["terminal-command-finished", "command-failed"] {
            registry.register(
                HookDescriptor(
                    category: .command,
                    name: hookName,
                    executableURL: URL(fileURLWithPath: "/usr/bin/true")
                )
            )
        }
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )

        let workspace = try controller.openWorkspace(at: "/tmp")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let runtimeSurfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)

        runtime.emit(.commandFinished(exitCode: 0, durationNanoseconds: 1), on: runtimeSurfaceID)

        XCTAssertEqual(launcher.invocations.map(\.name), ["terminal-command-finished"])
    }

    func testDiscoveredUserHookReceivesWorkspaceInvocation() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let workspaceHooksDirectory = tempDirectory
            .appending(path: "hooks")
            .appending(path: "workspace-opened")
        try FileManager.default.createDirectory(at: workspaceHooksDirectory, withIntermediateDirectories: true)

        let hookURL = workspaceHooksDirectory.appending(path: "10-capture")
        try """
        #!/bin/sh
        exit 0
        """.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookURL.path(percentEncoded: false)
        )

        let launcher = CapturingHookLauncher()
        let runner = ExternalHookRunner(
            registry: UserHookDirectoryDiscovery.registry(in: tempDirectory.appending(path: "hooks")),
            launcher: launcher
        )
        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: runner
        )

        let workspace = try controller.openWorkspace(at: "/tmp")

        let invocation = try XCTUnwrap(launcher.invocations.first)
        XCTAssertEqual(invocation.name, "workspace-opened")
        XCTAssertEqual(invocation.category, .lifecycle)
        XCTAssertEqual(invocation.workspaceID, workspace.id)
        XCTAssertEqual(invocation.payload.objectValue?["path"], .string("/tmp"))
    }

    func testWorkspaceOpenedHookMutationsAreNotOverwrittenByStaleOpenUpdate() throws {
        var controller: WorkspaceController!
        var changedPaneCounts: [Int] = []
        let registry = HookRegistry()
        registry.register(
            HookDescriptor(
                category: .lifecycle,
                name: "workspace-opened",
                executableURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
        let launcher = ClosureHookLauncher {
            _ = try controller.splitPane(target: .focused, axis: .rows)
        }
        controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )
        controller.onChange = { workspace in
            changedPaneCounts.append(workspace.focusedTab?.panes.count ?? 0)
        }

        let opened = try controller.openWorkspace(at: "/tmp")

        XCTAssertEqual(opened.focusedTab?.panes.count, 1)
        XCTAssertEqual(controller.activeWorkspace()?.focusedTab?.panes.count, 2)
        XCTAssertEqual(changedPaneCounts.first, 1)
        XCTAssertEqual(changedPaneCounts.last, 2)
    }

    @MainActor
    func testControlPlaneOpenWorkspaceWithoutPathUsesConfiguredDefaultRoot() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            defaultWorkspaceRootPath: "/tmp"
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "open.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()

        let requestFinished = expectation(description: "control-plane open request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketURL.path(percentEncoded: false))
                responseBox.value = try client.request(method: .openWorkspace, params: nil)
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertNil(responseBox.value?.error)
        XCTAssertEqual(controller.activeWorkspace()?.rootPath, "/tmp")
    }

    @MainActor
    func testControlPlaneNavigationMethodsReturnFocusedTerminalContext() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "navigation.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()

        let workspace = try controller.openWorkspace(at: "/tmp")
        let firstPaneID = try XCTUnwrap(workspace.focusedPane?.id)
        let withPaneTab = try XCTUnwrap(controller.createPaneTab())
        let secondPaneID = try XCTUnwrap(withPaneTab.focusedPane?.id)

        let nextTabResponse = try requestControlMethod(.focusNextPaneTab, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(nextTabResponse.error)
        XCTAssertEqual(targetPaneID(in: nextTabResponse), firstPaneID)

        let previousTabResponse = try requestControlMethod(.focusPreviousPaneTab, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(previousTabResponse.error)
        XCTAssertEqual(targetPaneID(in: previousTabResponse), secondPaneID)

        let singleVisiblePaneResponse = try requestControlMethod(.focusNextPane, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertEqual(singleVisiblePaneResponse.error?.code, 409)

        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        let nextPaneResponse = try requestControlMethod(.focusNextPane, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(nextPaneResponse.error)
        XCTAssertEqual(targetPaneID(in: nextPaneResponse), secondPaneID)

        let previousPaneResponse = try requestControlMethod(.focusPreviousPane, socketPath: socketURL.path(percentEncoded: false))
        XCTAssertNil(previousPaneResponse.error)
        XCTAssertEqual(targetPaneID(in: previousPaneResponse), splitPaneID)
    }

    @MainActor
    func testControlPlaneWorkspaceMutationsRunOnMainThreadForHookDrivenRequests() throws {
        let runtime = MainThreadRecordingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "control.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()
        _ = try controller.openWorkspace(at: "/tmp")

        let requestFinished = expectation(description: "control-plane split request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketURL.path(percentEncoded: false))
                let response = try client.request(
                    method: .splitPane,
                    params: .object(["axis": .string(PaneSplitAxis.rows.rawValue)])
                )
                responseBox.value = response
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertNil(responseBox.value?.error)
        XCTAssertEqual(runtime.nonMainThreadOperations, [])
        XCTAssertEqual(controller.activeWorkspace()?.focusedTab?.panes.count, 2)
    }

    @MainActor
    func testControlPlaneTerminalHistoryReturnsPaneMetadataAndInvalidPaneError() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )
        let configurationCoordinator = OpenMUXConfigurationCoordinator(
            bridge: bridge,
            initialState: OpenMUXPreparedConfiguration(
                theme: .defaultTheme,
                defaultWorkspaceRootPath: "/tmp",
                compiledConfigURL: nil,
                compiledHash: nil,
                diagnostics: []
            )
        )
        let socketURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "h.sock")
        let service = OpenMUXControlPlaneService(
            controller: controller,
            configurationCoordinator: configurationCoordinator,
            socketPath: socketURL.path(percentEncoded: false)
        )
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        try service.start()
        let workspace = try controller.openWorkspace(at: "/tmp/history")
        let pane = try XCTUnwrap(workspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        runtime.scrollbackBySurface[surfaceID] = "one\ntwo\nthree"

        let requestFinished = expectation(description: "history request finished")
        let responseBox = LockedBox<JSONRPCResponse?>(nil)
        let errorBox = LockedBox<Error?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let client = OmuxControlClient(socketPath: socketURL.path(percentEncoded: false))
                responseBox.value = try client.request(
                    method: .terminalHistory,
                    params: .object([
                        "paneID": .string(pane.id.rawValue),
                        "maxLines": .integer(2),
                        "maxBytes": .integer(1_000),
                    ])
                )
            } catch {
                errorBox.value = error
            }
            requestFinished.fulfill()
        }

        wait(for: [requestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertNil(responseBox.value?.error)
        guard case .object(let result)? = responseBox.value?.result,
              case .array(let items)? = result["items"],
              case .object(let item)? = items.first
        else {
            return XCTFail("expected history result")
        }
        XCTAssertEqual(item["workspaceID"], .string(workspace.id.rawValue))
        XCTAssertEqual(item["paneID"], .string(pane.id.rawValue))
        XCTAssertEqual(item["text"], .string("two\nthree"))
        XCTAssertEqual(item["truncated"], .bool(true))

        let invalidRequestFinished = expectation(description: "invalid history request finished")
        let invalidResponseBox = LockedBox<JSONRPCResponse?>(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                invalidResponseBox.value = try OmuxControlClient(socketPath: socketURL.path(percentEncoded: false)).request(
                    method: .terminalHistory,
                    params: .object(["paneID": .string("missing")])
                )
            } catch {
                errorBox.value = error
            }
            invalidRequestFinished.fulfill()
        }
        wait(for: [invalidRequestFinished], timeout: 3)

        XCTAssertNil(errorBox.value)
        XCTAssertEqual(invalidResponseBox.value?.error?.code, 404)
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
    private var transcriptBySurface: [String: String] = [:]
    private var inputBySurface: [String: String] = [:]
    private var terminalActionHandler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    var scrollbackBySurface: [String: String] = [:]
    var transcript = ""
    var sentTextCount = 0

    func createSurface(for paneID: PaneID) throws -> String {
        "action:\(paneID.rawValue)"
    }

    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        sessions[runtimeSurfaceID] = session
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        sessions.removeValue(forKey: runtimeSurfaceID)
        transcriptBySurface.removeValue(forKey: runtimeSurfaceID)
        inputBySurface.removeValue(forKey: runtimeSurfaceID)
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return NSView()
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        sessions[runtimeSurfaceID] != nil
    }

    func send(text: String, to runtimeSurfaceID: String) throws {
        guard sessions[runtimeSurfaceID] != nil else {
            throw TerminalBridgeError.runtimeAttachFailed(runtimeSurfaceID)
        }

        sentTextCount += 1
        inputBySurface[runtimeSurfaceID, default: ""].append(text)
    }

    func handle(_ event: NormalizedKeyEvent, on runtimeSurfaceID: String) throws {
        guard sessions[runtimeSurfaceID] != nil else {
            throw TerminalBridgeError.runtimeAttachFailed(runtimeSurfaceID)
        }

        guard event.phase == .keyDown, event.keyCode == 36 else {
            return
        }

        let command = inputBySurface[runtimeSurfaceID, default: ""]
        inputBySurface[runtimeSurfaceID] = ""
        execute(command: command, on: runtimeSurfaceID)
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
        defaultSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        guard sessions[runtimeSurfaceID] != nil else {
            return nil
        }

        let surfaceTranscript = transcript + transcriptBySurface[runtimeSurfaceID, default: ""]
        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: runtimeSurfaceID,
            transcript: surfaceTranscript,
            currentInput: inputBySurface[runtimeSurfaceID, default: ""],
            shell: descriptor.shell,
            workingDirectory: sessions[runtimeSurfaceID]?.workingDirectory ?? descriptor.workingDirectory,
            columns: defaultSize.columns,
            rows: defaultSize.rows
        )
    }

    func scrollbackSnapshot(runtimeSurfaceID: String, maxBytes: Int, maxLines: Int) -> PaneScrollbackSnapshot? {
        PaneScrollbackSnapshot.bounded(
            text: scrollbackBySurface[runtimeSurfaceID] ?? "",
            maxBytes: maxBytes,
            maxLines: maxLines
        )
    }

    func emit(_ action: TerminalAction, on runtimeSurfaceID: String) {
        if case .workingDirectoryChanged(let path) = action,
           var session = sessions[runtimeSurfaceID] {
            session.workingDirectory = path
            sessions[runtimeSurfaceID] = session
        }
        _ = terminalActionHandler?(RuntimeTerminalActionRecord(runtimeSurfaceID: runtimeSurfaceID, action: action))
    }

    private func execute(command: String, on runtimeSurfaceID: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }

        if trimmed.hasPrefix("cd ") {
            updateWorkingDirectory(String(trimmed.dropFirst(3)), on: runtimeSurfaceID)
            return
        }

        if trimmed == "pwd" {
            transcriptBySurface[runtimeSurfaceID, default: ""].append((sessions[runtimeSurfaceID]?.workingDirectory ?? "/tmp") + "\n")
            return
        }

        let output = trimmed
            .components(separatedBy: " && ")
            .compactMap(printfOutput)
            .joined()
        transcriptBySurface[runtimeSurfaceID, default: ""].append(output)
    }

    private func updateWorkingDirectory(_ path: String, on runtimeSurfaceID: String) {
        guard var session = sessions[runtimeSurfaceID] else {
            return
        }

        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("/") {
            session.workingDirectory = cleaned
        } else {
            session.workingDirectory = URL(fileURLWithPath: session.workingDirectory)
                .appendingPathComponent(cleaned)
                .standardizedFileURL
                .path
        }
        sessions[runtimeSurfaceID] = session
        emit(.workingDirectoryChanged(session.workingDirectory), on: runtimeSurfaceID)
    }

    private func printfOutput(from command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("printf '"), trimmed.hasSuffix("'") else {
            return nil
        }

        let start = trimmed.index(trimmed.startIndex, offsetBy: "printf '".count)
        let end = trimmed.index(before: trimmed.endIndex)
        return String(trimmed[start..<end])
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\'", with: "'")
    }
}

private final class MainThreadRecordingGhosttyRuntime: GhosttyRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: SessionDescriptor] = [:]
    private var recordedNonMainThreadOperations: [String] = []

    var nonMainThreadOperations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedNonMainThreadOperations
    }

    func createSurface(for paneID: PaneID) throws -> String {
        recordThread(operation: "createSurface")
        return "main-thread:\(paneID.rawValue)"
    }

    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        recordThread(operation: "attach")
        lock.lock()
        sessions[runtimeSurfaceID] = session
        lock.unlock()
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        recordThread(operation: "destroySurface")
        lock.lock()
        sessions.removeValue(forKey: runtimeSurfaceID)
        lock.unlock()
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return NSView()
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessions[runtimeSurfaceID] != nil
    }

    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        defaultSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        lock.lock()
        let hasSession = sessions[runtimeSurfaceID] != nil
        lock.unlock()
        guard hasSession else {
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
            columns: defaultSize.columns,
            rows: defaultSize.rows
        )
    }

    private func recordThread(operation: String) {
        guard Thread.isMainThread == false else {
            return
        }

        lock.lock()
        recordedNonMainThreadOperations.append(operation)
        lock.unlock()
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class CapturingHookLauncher: HookProcessLaunching, @unchecked Sendable {
    private(set) var invocations: [HookInvocation] = []

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = executableURL
        _ = arguments
        _ = environment
        invocations.append(try JSONDecoder().decode(HookInvocation.self, from: input))
    }
}

private final class ClosureHookLauncher: HookProcessLaunching, @unchecked Sendable {
    private let body: () throws -> Void

    init(body: @escaping () throws -> Void) {
        self.body = body
    }

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = executableURL
        _ = arguments
        _ = environment
        _ = input
        try body()
    }
}
