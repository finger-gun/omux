import Foundation
import OmuxControlPlane
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

    func emitControlPlaneEvent(_ event: ControlPlaneEvent) {
        controlPlaneEventSink(event)
    }
}
