import AppKit
import Foundation
import OmuxControlPlane
import OmuxCore
import OmuxHooks
import OmuxTerminalBridge

@MainActor
public final class OpenMUXAppDelegate: NSObject, NSApplicationDelegate {
    private let workspaceController: WorkspaceController
    private let controlPlaneService: OpenMUXControlPlaneService
    private var windowController: WorkspaceWindowController?

    public override init() {
        let bridge = GhosttyTerminalBridge()
        let hookRunner = ExternalHookRunner()
        let workspaceController = WorkspaceController(bridge: bridge, hookRunner: hookRunner)
        self.workspaceController = workspaceController
        self.controlPlaneService = OpenMUXControlPlaneService(controller: workspaceController)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        workspaceController.onChange = { [weak self] workspace in
            Task { @MainActor in
                self?.windowController?.update(workspace: workspace)
            }
        }

        do {
            let workspace = try workspaceController.openWorkspace(at: FileManager.default.currentDirectoryPath)
            let windowController = WorkspaceWindowController(workspace: workspace, controller: workspaceController)
            self.windowController = windowController
            windowController.showWindow(nil)
            try controlPlaneService.start()
        } catch {
            assertionFailure("Failed to launch OpenMUX foundation: \(error)")
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        controlPlaneService.stop()
    }
}
