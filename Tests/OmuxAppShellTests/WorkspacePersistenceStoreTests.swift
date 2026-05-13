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

    func testWorkspacePersistenceStoreUsesFileBackedStateWhenProvided() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        let stateFileURL = root
            .appendingPathComponent("WorkspaceState", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = WorkspacePersistenceStore(defaults: defaults, stateFileURL: stateFileURL)
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

        XCTAssertTrue(FileManager.default.fileExists(atPath: stateFileURL.path))
        XCTAssertNil(defaults.data(forKey: "dev.fingergun.omux.workspacePersistence"))
        XCTAssertEqual(WorkspacePersistenceStore(defaults: defaults, stateFileURL: stateFileURL).load(), snapshot)
    }

    func testWorkspacePersistenceStorePersistsScrollbackPayloadsOutsideStateFile() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        let stateFileURL = root
            .appendingPathComponent("WorkspaceState", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
        let scrollbackDirectory = root.appendingPathComponent("Scrollback", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = WorkspacePersistenceStore(
            defaults: defaults,
            stateFileURL: stateFileURL,
            scrollbackPayloadStore: WorkspaceScrollbackPayloadStore(directoryURL: scrollbackDirectory)
        )
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let scrollback = PaneScrollbackSnapshot(text: "\u{001B}[31mred output\u{001B}[0m", truncated: false)
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

        store.save(snapshot)

        let stateJSON = try String(contentsOf: stateFileURL, encoding: .utf8)
        XCTAssertFalse(stateJSON.contains("red output"))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.workspaces.first?.focusedPane?.terminalState.restoredScrollback?.text, scrollback.text)

        let storageIdentifier = try XCTUnwrap(
            JSONDecoder()
                .decode(WorkspacePersistenceSnapshot.self, from: Data(contentsOf: stateFileURL))
                .workspaces.first?
                .focusedPane?
                .terminalState
                .restoredScrollback?
                .storageIdentifier
        )
        let payloadURL = scrollbackDirectory.appendingPathComponent(storageIdentifier)
        XCTAssertEqual(try String(contentsOf: payloadURL, encoding: .utf8), scrollback.text)
        let attributes = try FileManager.default.attributesOfItem(atPath: payloadURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

        var clearedPane = pane
        clearedPane.terminalState.restoredScrollback = nil
        let clearedTab = Tab(title: "Main", panes: [clearedPane], focusedPaneID: clearedPane.id)
        let clearedWorkspace = Workspace(
            id: workspace.id,
            generatedName: workspace.generatedName,
            customName: workspace.customName,
            rootPath: workspace.rootPath,
            tabs: [clearedTab],
            focusedTabID: clearedTab.id
        )

        store.save(WorkspacePersistenceSnapshot(workspaces: [clearedWorkspace], activeWorkspaceID: workspace.id))

        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testWorkspacePersistenceStartupLoadOnlyResolvesInitiallyVisibleScrollbackPayloads() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        let stateFileURL = root
            .appendingPathComponent("WorkspaceState", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
        let scrollbackDirectory = root.appendingPathComponent("Scrollback", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = WorkspacePersistenceStore(
            defaults: defaults,
            stateFileURL: stateFileURL,
            scrollbackPayloadStore: WorkspaceScrollbackPayloadStore(directoryURL: scrollbackDirectory)
        )
        let visiblePane = Pane(
            title: "visible",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/visible"),
            terminalState: PaneTerminalState(restoredScrollback: PaneScrollbackSnapshot(text: "visible output", truncated: false))
        )
        let hiddenPane = Pane(
            title: "hidden",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/hidden"),
            terminalState: PaneTerminalState(restoredScrollback: PaneScrollbackSnapshot(text: "hidden output", truncated: false))
        )
        let hiddenTab = Tab(title: "Hidden", panes: [hiddenPane], focusedPaneID: hiddenPane.id)
        let visibleTab = Tab(title: "Visible", panes: [visiblePane], focusedPaneID: visiblePane.id)
        let workspace = Workspace(
            generatedName: "Workspace 1",
            rootPath: "/tmp/project",
            tabs: [hiddenTab, visibleTab],
            focusedTabID: visibleTab.id
        )
        let snapshot = WorkspacePersistenceSnapshot(
            workspaces: [workspace],
            activeWorkspaceID: workspace.id
        )

        store.save(snapshot)

        let startupSnapshot = try XCTUnwrap(store.load(scrollbackPayloadResolution: .initiallyVisible))
        let startupWorkspace = try XCTUnwrap(startupSnapshot.workspaces.first)
        let startupHiddenPane = try XCTUnwrap(startupWorkspace.tabs.first(where: { $0.id == hiddenTab.id })?.panes.first)
        let startupVisiblePane = try XCTUnwrap(startupWorkspace.tabs.first(where: { $0.id == visibleTab.id })?.panes.first)

        XCTAssertEqual(startupVisiblePane.terminalState.restoredScrollback?.text, "visible output")
        XCTAssertNotNil(startupVisiblePane.terminalState.restoredScrollback?.storageIdentifier)
        XCTAssertEqual(startupHiddenPane.terminalState.restoredScrollback?.text, "")
        XCTAssertNotNil(startupHiddenPane.terminalState.restoredScrollback?.storageIdentifier)

        let fullSnapshot = try XCTUnwrap(store.load())
        let fullHiddenPane = try XCTUnwrap(fullSnapshot.workspaces.first?.tabs.first(where: { $0.id == hiddenTab.id })?.panes.first)
        XCTAssertEqual(fullHiddenPane.terminalState.restoredScrollback?.text, "hidden output")
    }

    func testWorkspacePersistenceStorePreservesFloatingPaneModalsWhenPersistingScrollbackPayloads() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        let stateFileURL = root
            .appendingPathComponent("WorkspaceState", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
        let scrollbackDirectory = root.appendingPathComponent("Scrollback", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = WorkspacePersistenceStore(
            defaults: defaults,
            stateFileURL: stateFileURL,
            scrollbackPayloadStore: WorkspaceScrollbackPayloadStore(directoryURL: scrollbackDirectory)
        )
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp/project")
        let dockedPane = Pane(title: "main", session: session)
        let tab = Tab(title: "Main", panes: [dockedPane], focusedPaneID: dockedPane.id)
        let modalScrollback = PaneScrollbackSnapshot(text: "modal output", truncated: false)
        let modalPane = Pane(
            title: "modal",
            session: session,
            terminalState: PaneTerminalState(restoredScrollback: modalScrollback)
        )
        let modal = FloatingPaneModal(
            paneStack: PaneStack(panes: [modalPane], focusedPaneID: modalPane.id),
            frame: FloatingPaneModalFrame(x: 48, y: 64, width: 680, height: 480)
        )
        let workspace = Workspace(
            generatedName: "Workspace 1",
            rootPath: "/tmp/project",
            tabs: [tab],
            focusedTabID: tab.id,
            floatingPaneModals: [modal],
            focusedFloatingPaneModalID: modal.id
        )
        let snapshot = WorkspacePersistenceSnapshot(workspaces: [workspace], activeWorkspaceID: workspace.id)

        store.save(snapshot)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.activeWorkspaceID, snapshot.activeWorkspaceID)
        XCTAssertEqual(loaded.workspaces.first?.floatingPaneModals.first?.id, modal.id)
        XCTAssertEqual(loaded.workspaces.first?.focusedFloatingPaneModalID, modal.id)
        XCTAssertEqual(
            loaded.workspaces.first?.floatingPaneModals.first?.paneStack.panes.first?.terminalState.restoredScrollback?.text,
            modalScrollback.text
        )
    }

    func testWorkspacePersistenceStoreMigratesDefaultsSnapshotToFileBackedState() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        let stateFileURL = root
            .appendingPathComponent("WorkspaceState", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let legacyStore = WorkspacePersistenceStore(defaults: defaults)
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
        legacyStore.save(snapshot)

        let fileBackedStore = WorkspacePersistenceStore(defaults: defaults, stateFileURL: stateFileURL)

        XCTAssertEqual(fileBackedStore.load(), snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateFileURL.path))
        XCTAssertNil(defaults.data(forKey: "dev.fingergun.omux.workspacePersistence"))
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

    func testWorkspacePersistenceStoreBacksUpFileBackedStateWhenCleared() throws {
        let suiteName = "WorkspacePersistenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        let stateFileURL = root
            .appendingPathComponent("WorkspaceState", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
        let backupDirectory = root.appendingPathComponent("WorkspaceBackups", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = WorkspacePersistenceStore(
            defaults: defaults,
            stateFileURL: stateFileURL,
            backupDirectory: backupDirectory
        )
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

        XCTAssertFalse(FileManager.default.fileExists(atPath: stateFileURL.path))
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
