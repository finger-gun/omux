import AppKit
import Foundation
import OmuxControlPlane
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge

protocol TerminalActionHostHandling {
    func openURL(_ url: String)
    func presentNotification(_ request: NotificationRequest)
    func ringBell()
    func handleCommandFinished(_ event: TerminalActionEvent, context: ControlPlaneTerminalContext)
}

struct DefaultTerminalActionHostHandler: TerminalActionHostHandling {
    let controller: WorkspaceController

    func openURL(_ url: String) {
        let targetURL = URL(string: url) ?? URL(fileURLWithPath: url)
        DispatchQueue.main.async {
            NSWorkspace.shared.open(targetURL)
        }
    }

    func presentNotification(_ request: NotificationRequest) {
        controller.deliverNotification(request)
    }

    func ringBell() {
        DispatchQueue.main.async {
            NSSound.beep()
        }
    }

    func handleCommandFinished(_ event: TerminalActionEvent, context: ControlPlaneTerminalContext) {
        guard case .commandFinished(let exitCode, _) = event.action else {
            return
        }

        let title = exitCode == 0 ? "Command finished" : "Command failed"
        let body = exitCode.map { "Pane \(context.paneID.rawValue) exited with code \($0)." } ?? "Pane \(context.paneID.rawValue) reported completion."
        presentNotification(NotificationRequest(title: title, body: body))
    }
}

final class TerminalActionCoordinator {
    private let bridge: GhosttyTerminalBridge
    private unowned let controller: WorkspaceController
    private let hookRunner: ExternalHookRunner
    private let hostHandler: any TerminalActionHostHandling
    private let observerToken: UUID

    init(
        bridge: GhosttyTerminalBridge,
        controller: WorkspaceController,
        hookRunner: ExternalHookRunner,
        hostHandler: (any TerminalActionHostHandling)? = nil
    ) {
        self.bridge = bridge
        self.controller = controller
        self.hookRunner = hookRunner
        self.hostHandler = hostHandler ?? DefaultTerminalActionHostHandler(controller: controller)
        self.observerToken = bridge.addTerminalActionObserver { [weak controller] event in
            controller?.terminalActionCoordinatorHandle(event)
        }
    }

    deinit {
        bridge.removeTerminalActionObserver(token: observerToken)
    }

    func handle(_ event: TerminalActionEvent) {
        guard let context = controller.applyTerminalActionState(event) else {
            return
        }

        let payload = controller.enrichedCommandCompletionPayload(for: event, context: context)
        do {
            try hookRunner.emit(
                HookInvocation(
                    category: hookCategory(for: event.action),
                    name: event.action.hookName,
                    workspaceID: context.workspaceID,
                    tabID: context.tabID,
                    paneID: context.paneID,
                    sessionID: context.sessionID,
                    payload: payload
                )
            )
            if case .commandFinished(let exitCode, _) = event.action,
               let exitCode,
               exitCode != 0 {
                try hookRunner.emit(
                    HookInvocation(
                        category: .command,
                        name: "command-failed",
                        workspaceID: context.workspaceID,
                        tabID: context.tabID,
                        paneID: context.paneID,
                        sessionID: context.sessionID,
                        payload: payload
                    )
                )
            }
        } catch {
            fputs("warning: failed to emit terminal action hook \(event.action.hookName): \(error)\n", stderr)
        }

        controller.publishTerminalEvent(makeControlPlaneEvent(from: event, context: context, payload: payload))

        switch event.action {
        case .openURL(let url, _):
            hostHandler.openURL(url)
        case .desktopNotification(let title, let body):
            hostHandler.presentNotification(NotificationRequest(title: title, body: body ?? ""))
        case .bell:
            hostHandler.ringBell()
        case .commandFinished:
            hostHandler.handleCommandFinished(event, context: context)
        default:
            break
        }
    }

    private func hookCategory(for action: TerminalAction) -> HookCategory {
        switch action {
        case .inputSent:
            return .input
        case .commandFinished:
            return .command
        case .openURL, .desktopNotification, .bell:
            return .ui
        default:
            return .session
        }
    }

    private func makeControlPlaneEvent(
        from event: TerminalActionEvent,
        context: ControlPlaneTerminalContext,
        payload: OmuxValue
    ) -> ControlPlaneTerminalEvent {
        let name: ControlPlaneTerminalEventName
        switch event.action {
        case .workingDirectoryChanged:
            name = .workingDirectoryChanged
        case .titleChanged:
            name = .titleChanged
        case .tabTitleChanged:
            name = .tabTitleChanged
        case .openURL:
            name = .openURL
        case .desktopNotification:
            name = .desktopNotification
        case .bell:
            name = .bell
        case .inputSent:
            name = .inputSent
        case .commandFinished:
            name = .commandFinished
        case .progressReported:
            name = .progressReported
        case .childExited:
            name = .childExited
        case .rendererHealthChanged:
            name = .rendererHealthChanged
        }

        return ControlPlaneTerminalEvent(
            name: name,
            workspaceID: context.workspaceID,
            tabID: context.tabID,
            paneID: context.paneID,
            sessionID: context.sessionID,
            payload: payload
        )
    }
}
