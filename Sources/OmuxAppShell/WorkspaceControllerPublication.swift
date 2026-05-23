import Foundation
import OmuxControlPlane
import OmuxCore
import OmuxHooks

final class WorkspaceControllerPublication {
    private let hookRunner: ExternalHookRunner
    private let controlPlaneEventSink: (ControlPlaneEvent) -> Void

    init(
        hookRunner: ExternalHookRunner,
        controlPlaneEventSink: @escaping (ControlPlaneEvent) -> Void
    ) {
        self.hookRunner = hookRunner
        self.controlPlaneEventSink = controlPlaneEventSink
    }

    func emitHook(_ invocation: HookInvocation) throws {
        try hookRunner.emit(invocation)
    }

    func emitHook(
        category: HookCategory,
        name: String,
        workspaceID: WorkspaceID? = nil,
        tabID: TabID? = nil,
        paneID: PaneID? = nil,
        sessionID: SessionID? = nil,
        payload: OmuxValue = .object([:])
    ) throws {
        try emitHook(
            HookInvocation(
                category: category,
                name: name,
                workspaceID: workspaceID,
                tabID: tabID,
                paneID: paneID,
                sessionID: sessionID,
                payload: payload
            )
        )
    }

    func emitControlPlaneEvent(_ event: ControlPlaneEvent) {
        controlPlaneEventSink(event)
    }

    func emitActionEvent(
        name: ControlPlaneActionEventName,
        workspaceID: WorkspaceID? = nil,
        tabID: TabID? = nil,
        paneID: PaneID? = nil,
        sessionID: SessionID? = nil,
        payload: OmuxValue = .object([:])
    ) {
        emitControlPlaneEvent(
            ControlPlaneEvent(
                name: name,
                workspaceID: workspaceID,
                tabID: tabID,
                paneID: paneID,
                sessionID: sessionID,
                payload: payload
            )
        )
    }
}
