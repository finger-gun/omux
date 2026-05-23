import XCTest
@testable import OmuxAppShell
import OmuxControlPlane
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge

final class WorkspaceControllerRefactorParityTests: XCTestCase {
    func testWorkspaceControllerLookupIndexMatchesWorkspaceScanAcrossMutations() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner()
        )

        var workspace = try controller.openWorkspace(at: "/tmp/refactor-scan-a")
        let firstPane = try XCTUnwrap(workspace.focusedPane)
        workspace = try XCTUnwrap(controller.splitFocusedPane(axis: .columns))
        let secondPane = try XCTUnwrap(workspace.focusedPane)
        _ = try controller.createTab()
        let workspaceB = try controller.createWorkspace()

        let cases: [ControlPlaneTerminalTarget] = [
            .pane(firstPane.id),
            .pane(secondPane.id),
            .session(firstPane.session.id),
            .session(secondPane.session.id),
            .workspace(workspaceB.id),
            .focused,
        ]

        for target in cases {
            let indexed = controller.resolveTerminalTarget(target)
            let scanned = scannedContext(for: target, controller: controller)
            XCTAssertEqual(indexed?.workspaceID, scanned?.workspaceID)
            XCTAssertEqual(indexed?.tabID, scanned?.tabID)
            XCTAssertEqual(indexed?.paneID, scanned?.paneID)
            XCTAssertEqual(indexed?.sessionID, scanned?.sessionID)
        }

        _ = try controller.closePane(paneID: secondPane.id)
        let remainingTargets: [ControlPlaneTerminalTarget] = [
            .pane(firstPane.id),
            .session(firstPane.session.id),
            .focused,
        ]
        for target in remainingTargets {
            let indexed = controller.resolveTerminalTarget(target)
            let scanned = scannedContext(for: target, controller: controller)
            XCTAssertEqual(indexed?.workspaceID, scanned?.workspaceID)
            XCTAssertEqual(indexed?.tabID, scanned?.tabID)
            XCTAssertEqual(indexed?.paneID, scanned?.paneID)
            XCTAssertEqual(indexed?.sessionID, scanned?.sessionID)
        }
    }

    func testWorkspaceControllerPublicationSeamPreservesOrderingAndPayloads() throws {
        let runtime = ActionEmittingGhosttyRuntime()
        let launcher = RecordingHookLauncher()
        let registry = HookRegistry()
        registry.register(HookDescriptor(category: .lifecycle, name: "workspace-opened", executableURL: URL(fileURLWithPath: "/usr/bin/true")))
        registry.register(HookDescriptor(category: .lifecycle, name: "workspace-closed", executableURL: URL(fileURLWithPath: "/usr/bin/true")))
        registry.register(HookDescriptor(category: .session, name: "pane-created", executableURL: URL(fileURLWithPath: "/usr/bin/true")))
        registry.register(HookDescriptor(category: .session, name: "pane-focused", executableURL: URL(fileURLWithPath: "/usr/bin/true")))

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: runtime),
            hookRunner: ExternalHookRunner(registry: registry, launcher: launcher)
        )

        var sequence: [String] = []
        var events: [ControlPlaneEvent] = []
        controller.onControlPlaneEvent = { event in
            events.append(event)
            sequence.append("event:\(event.name)")
        }
        launcher.onInvocation = { invocation in
            sequence.append("hook:\(invocation.name)")
        }

        let firstWorkspace = try controller.openWorkspace(at: "/tmp/refactor-publish-a")
        let firstSessionID = try XCTUnwrap(firstWorkspace.focusedPane?.session.id)
        let splitWorkspace = try XCTUnwrap(controller.splitFocusedPane(axis: .rows))
        let splitPaneID = try XCTUnwrap(splitWorkspace.focusedPane?.id)
        XCTAssertTrue(try controller.focus(sessionID: firstSessionID))
        let secondWorkspace = try controller.openWorkspace(at: "/tmp/refactor-publish-b")
        _ = try XCTUnwrap(controller.closeWorkspace(secondWorkspace.id))
        let restoredWorkspace = try XCTUnwrap(controller.restore(workspaceID: firstWorkspace.id))

        XCTAssertEqual(restoredWorkspace.id, firstWorkspace.id)
        XCTAssertEqual(sequence, [
            "event:workspace.opened",
            "hook:workspace-opened",
            "hook:pane-created",
            "event:pane.split",
            "hook:pane-focused",
            "event:session.focused",
            "event:workspace.opened",
            "hook:workspace-opened",
            "hook:workspace-closed",
            "event:workspace.restored",
        ])

        XCTAssertEqual(events.map(\.name), [
            "workspace.opened",
            "pane.split",
            "session.focused",
            "workspace.opened",
            "workspace.restored",
        ])
        XCTAssertEqual(events[0].payload.objectValue?["path"], .string("/tmp/refactor-publish-a"))
        XCTAssertEqual(events[1].payload.objectValue?["axis"], .string("rows"))
        XCTAssertEqual(events[1].paneID, splitPaneID)
        XCTAssertEqual(events[2].sessionID, firstSessionID)
        XCTAssertEqual(events[3].payload.objectValue?["path"], .string("/tmp/refactor-publish-b"))
        XCTAssertEqual(events[4].workspaceID, firstWorkspace.id)
        XCTAssertEqual(events[4].payload.objectValue?.count, 0)

        XCTAssertEqual(launcher.invocations.map(\.name), [
            "workspace-opened",
            "pane-created",
            "pane-focused",
            "workspace-opened",
            "workspace-closed",
        ])
        XCTAssertEqual(launcher.invocations[0].payload.objectValue?["path"], .string("/tmp/refactor-publish-a"))
        XCTAssertEqual(launcher.invocations[1].workspaceID, firstWorkspace.id)
        XCTAssertEqual(launcher.invocations[1].paneID, splitPaneID)
        XCTAssertEqual(launcher.invocations[2].sessionID, firstSessionID)
        XCTAssertEqual(launcher.invocations[3].payload.objectValue?["path"], .string("/tmp/refactor-publish-b"))
        XCTAssertEqual(launcher.invocations[4].payload.objectValue?["path"], .string("/tmp/refactor-publish-b"))
    }

    private func scannedContext(
        for target: ControlPlaneTerminalTarget,
        controller: WorkspaceController
    ) -> ControlPlaneTerminalContext? {
        let workspaces = controller.allWorkspaces()
        switch target {
        case .pane(let paneID):
            for workspace in workspaces {
                for tab in workspace.tabs {
                    if let pane = tab.panes.first(where: { $0.id == paneID }),
                       let sessionID = pane.terminalSession?.id {
                        return ControlPlaneTerminalContext(
                            workspaceID: workspace.id,
                            tabID: tab.id,
                            paneStackID: tab.rootLayout.paneStack(containingPaneID: pane.id)?.id,
                            paneID: pane.id,
                            sessionID: sessionID
                        )
                    }
                }
            }
        case .session(let sessionID):
            for workspace in workspaces {
                for tab in workspace.tabs {
                    if let pane = tab.panes.first(where: { $0.terminalSession?.id == sessionID }) {
                        return ControlPlaneTerminalContext(
                            workspaceID: workspace.id,
                            tabID: tab.id,
                            paneStackID: tab.rootLayout.paneStack(containingPaneID: pane.id)?.id,
                            paneID: pane.id,
                            sessionID: sessionID
                        )
                    }
                }
            }
        case .tab(let tabID):
            for workspace in workspaces {
                if let tab = workspace.tabs.first(where: { $0.id == tabID }),
                   let pane = tab.focusedPane,
                   let sessionID = pane.terminalSession?.id {
                    return ControlPlaneTerminalContext(
                        workspaceID: workspace.id,
                        tabID: tab.id,
                        paneStackID: tab.rootLayout.paneStack(containingPaneID: pane.id)?.id,
                        paneID: pane.id,
                        sessionID: sessionID
                    )
                }
            }
        case .workspace(let workspaceID):
            guard let workspace = workspaces.first(where: { $0.id == workspaceID }),
                  let tab = workspace.focusedTab,
                  let pane = tab.focusedPane,
                  let sessionID = pane.terminalSession?.id
            else {
                return nil
            }
            return ControlPlaneTerminalContext(
                workspaceID: workspace.id,
                tabID: tab.id,
                paneStackID: tab.rootLayout.paneStack(containingPaneID: pane.id)?.id,
                paneID: pane.id,
                sessionID: sessionID
            )
        case .focused:
            guard let workspace = controller.activeWorkspace(),
                  let tab = workspace.focusedTab,
                  let pane = tab.focusedPane,
                  let sessionID = pane.terminalSession?.id
            else {
                return nil
            }
            return ControlPlaneTerminalContext(
                workspaceID: workspace.id,
                tabID: tab.id,
                paneStackID: tab.rootLayout.paneStack(containingPaneID: pane.id)?.id,
                paneID: pane.id,
                sessionID: sessionID
            )
        }

        return nil
    }
}

private final class RecordingHookLauncher: HookProcessLaunching, @unchecked Sendable {
    private(set) var invocations: [HookInvocation] = []
    var onInvocation: ((HookInvocation) -> Void)?

    func launch(executableURL: URL, arguments: [String], environment: [String: String], input: Data) throws {
        _ = executableURL
        _ = arguments
        _ = environment
        let invocation = try JSONDecoder().decode(HookInvocation.self, from: input)
        invocations.append(invocation)
        onInvocation?(invocation)
    }
}
