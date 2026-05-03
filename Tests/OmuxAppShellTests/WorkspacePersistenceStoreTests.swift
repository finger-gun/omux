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

    func testWorkspacePersistenceStoreMigratesFallbackSnapshot() throws {
        let primarySuiteName = "WorkspacePersistenceStoreTests-primary-\(UUID().uuidString)"
        let fallbackSuiteName = "WorkspacePersistenceStoreTests-fallback-\(UUID().uuidString)"
        let primaryDefaults = try XCTUnwrap(UserDefaults(suiteName: primarySuiteName))
        let fallbackDefaults = try XCTUnwrap(UserDefaults(suiteName: fallbackSuiteName))
        primaryDefaults.removePersistentDomain(forName: primarySuiteName)
        fallbackDefaults.removePersistentDomain(forName: fallbackSuiteName)
        defer {
            primaryDefaults.removePersistentDomain(forName: primarySuiteName)
            fallbackDefaults.removePersistentDomain(forName: fallbackSuiteName)
        }

        let fallbackStore = WorkspacePersistenceStore(defaults: fallbackDefaults)
        let primaryStore = WorkspacePersistenceStore(
            defaults: primaryDefaults,
            fallbackDefaults: fallbackDefaults
        )
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let scrollback = PaneScrollbackSnapshot(text: "restored output", truncated: false)
        let pane = Pane(
            title: "hx",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: scrollback)
        )
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

        fallbackStore.save(snapshot)

        XCTAssertEqual(primaryStore.load(), snapshot)
        XCTAssertEqual(WorkspacePersistenceStore(defaults: primaryDefaults).load(), snapshot)
        XCTAssertEqual(fallbackStore.load(), snapshot)
    }

    func testWorkspacePersistenceStoreRestoresLatestBackupWhenDefaultsAreMissing() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let backupDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: backupDirectory)
        }

        let store = WorkspacePersistenceStore(defaults: defaults, backupDirectory: backupDirectory)
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
        store.save(nil)

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
