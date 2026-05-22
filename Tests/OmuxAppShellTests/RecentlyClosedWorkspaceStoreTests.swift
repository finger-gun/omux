import Foundation
import XCTest
@testable import OmuxAppShell
@testable import OmuxCore

final class RecentlyClosedWorkspaceStoreTests: XCTestCase {
    func testRecentlyClosedWorkspaceStorePreservesEntriesSharingWorkingDirectoryAndClears() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentlyClosedWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("recently-closed.json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = RecentlyClosedWorkspaceStore(fileURL: fileURL)
        let sharedPath = "/tmp/project"
        let first = makeWorkspace(name: "First", workingDirectory: sharedPath)
        let second = makeWorkspace(name: "Second", workingDirectory: sharedPath)

        store.add(first)
        store.add(second)

        let entries = store.load()
        XCTAssertEqual(entries.map(\.name), ["Second", "First"])
        XCTAssertEqual(entries.map(\.workspacePaths), [[sharedPath], [sharedPath]])
        XCTAssertEqual(store.find(byPath: sharedPath)?.id, second.id)

        store.clear()

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertNil(store.find(byPath: sharedPath))
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
