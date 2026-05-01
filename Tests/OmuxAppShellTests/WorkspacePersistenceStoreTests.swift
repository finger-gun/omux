import Foundation
import XCTest
@testable import OmuxAppShell
@testable import OmuxCore

@MainActor
final class WorkspacePersistenceStoreTests: XCTestCase {
    func testWorkspacePersistenceStoreRoundTripsSnapshot() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkspacePersistenceStore(defaults: defaults)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let pane = Pane(title: "hx", session: session)
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(
            generatedName: "Workspace 1",
            customName: "Client Shell",
            rootPath: "/tmp/project",
            tabs: [tab],
            focusedTabID: tab.id
        )
        let snapshot = WorkspacePersistenceSnapshot(
            workspaces: [workspace],
            activeWorkspaceID: workspace.id
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }

    func testWorkspacePersistenceStoreClearsSavedSnapshot() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkspacePersistenceStore(defaults: defaults)
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        let pane = Pane(title: "tmp", session: session)
        let tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)
        let workspace = Workspace(generatedName: "Workspace 1", rootPath: "/tmp", tabs: [tab], focusedTabID: tab.id)

        store.save(.init(workspaces: [workspace], activeWorkspaceID: workspace.id))
        store.save(nil)

        XCTAssertNil(store.load())
    }
}
