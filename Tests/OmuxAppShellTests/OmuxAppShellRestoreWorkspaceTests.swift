import Foundation
import XCTest
@testable import OmuxControlPlane
@testable import OmuxAppShell
@testable import OmuxCore
@testable import OmuxHooks
@testable import OmuxTerminalBridge

final class OmuxAppShellRestoreWorkspaceTests: XCTestCase {
    func testWorkingDirectoryChangeOffersMatchingRecentlyClosedWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmuxAppShellRestoreWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        let store = RecentlyClosedWorkspaceStore(fileURL: root.appendingPathComponent("recently-closed.json", isDirectory: false))
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = ActionEmittingGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let controller = WorkspaceController(
            bridge: bridge,
            hookRunner: ExternalHookRunner(),
            recentlyClosedStore: store
        )
        let closedWorkspace = makeWorkspace(name: "FLX AI CAMERA", workingDirectory: "/tmp/flx-ai-camera")
        store.add(closedWorkspace)

        let activeWorkspace = try controller.openWorkspace(at: "/tmp/scratch")
        let pane = try XCTUnwrap(activeWorkspace.focusedPane)
        let surfaceID = try XCTUnwrap(bridge.surface(for: pane.id)?.runtimeSurfaceID)
        let offerExpectation = expectation(description: "restore offer delivered")
        var offeredEntry: RecentlyClosedWorkspaceEntry?
        controller.onRestoreOffer = { entry in
            offeredEntry = entry
            offerExpectation.fulfill()
        }

        runtime.emit(.workingDirectoryChanged("/tmp/flx-ai-camera"), on: surfaceID)

        wait(for: [offerExpectation], timeout: 1)
        XCTAssertEqual(offeredEntry?.id, closedWorkspace.id)
        XCTAssertEqual(offeredEntry?.name, "FLX AI CAMERA")
    }

    func testCommandPaletteRecentlyClosedCommandsReflectStoreStateAndClearEntries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmuxAppShellRestoreWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        let store = RecentlyClosedWorkspaceStore(fileURL: root.appendingPathComponent("recently-closed.json", isDirectory: false))
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = WorkspaceController(
            bridge: GhosttyTerminalBridge(runtime: ActionEmittingGhosttyRuntime()),
            hookRunner: ExternalHookRunner(),
            recentlyClosedStore: store
        )
        store.add(makeWorkspace(name: "GENERAL", workingDirectory: "/tmp/general"))

        let commands = CommandPaletteCommandCatalog.commands(controller: controller, keyBindings: .defaults)
        let restore = try XCTUnwrap(commands.first { $0.id == "builtin:restore-workspace" })
        let clear = try XCTUnwrap(commands.first { $0.id == "builtin:clear-recently-closed-workspaces" })

        XCTAssertTrue(restore.isEnabled)
        XCTAssertTrue(clear.isEnabled)
        XCTAssertEqual(restore.disabledReason, nil)
        XCTAssertEqual(clear.disabledReason, nil)
        XCTAssertEqual(controller.invokeCommandPaletteResult(CommandPaletteResult(
            id: clear.id,
            title: clear.title,
            subtitle: clear.subtitle,
            category: clear.category,
            matchText: clear.matchText,
            aliases: clear.aliases,
            shortcutLabel: clear.shortcutLabel,
            isEnabled: clear.isEnabled,
            invocationTarget: clear.invocationTarget
        )), .invoked)
        XCTAssertTrue(store.load().isEmpty)

        let commandsAfterClear = CommandPaletteCommandCatalog.commands(controller: controller, keyBindings: .defaults)
        let restoreAfterClear = try XCTUnwrap(commandsAfterClear.first { $0.id == "builtin:restore-workspace" })
        let clearAfterClear = try XCTUnwrap(commandsAfterClear.first { $0.id == "builtin:clear-recently-closed-workspaces" })
        XCTAssertFalse(restoreAfterClear.isEnabled)
        XCTAssertEqual(restoreAfterClear.disabledReason, "No recently closed workspaces")
        XCTAssertFalse(clearAfterClear.isEnabled)
        XCTAssertEqual(clearAfterClear.disabledReason, "No recently closed workspaces")
    }

    private func makeWorkspace(name: String, workingDirectory: String) -> Workspace {
        let pane = Pane(title: name, session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: workingDirectory))
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        return Workspace(
            generatedName: name,
            customName: name,
            rootPath: workingDirectory,
            tabs: [tab],
            focusedTabID: tab.id
        )
    }
}
