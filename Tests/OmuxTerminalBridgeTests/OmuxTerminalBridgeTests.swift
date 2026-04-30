import Foundation
import XCTest
@testable import OmuxCore
@testable import OmuxTerminalBridge

final class OmuxTerminalBridgeTests: XCTestCase {
    func testBridgeOwnsSurfaceLifecycle() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        let surface = try bridge.createSurface(for: pane)
        let attachment = try bridge.attach(session: session, to: pane)

        XCTAssertEqual(surface.paneID, pane.id)
        XCTAssertEqual(attachment.sessionID, session.id)
        XCTAssertEqual(bridge.attachedSession(for: pane.id), session.id)

        try bridge.teardown(paneID: pane.id)
        XCTAssertNil(bridge.surface(for: pane.id))
    }

    func testOnlyTerminalBridgeMayMentionCGhostty() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let sourcesURL = repositoryRoot.appending(path: "Sources")
        let enumerator = FileManager.default.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: nil
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else {
                continue
            }

            if fileURL.path.contains("/OmuxTerminalBridge/") {
                continue
            }

            let contents = try String(contentsOf: fileURL)
            XCTAssertFalse(contents.contains("CGhostty"), "CGhostty leaked outside OmuxTerminalBridge in \(fileURL.path)")
        }
    }

    @MainActor
    func testTerminalSessionSnapshotsUpdateWhenCommandRuns() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)
        try bridge.run(command: "printf 'hello from shell'", inPane: pane.id)

        let expectation = expectation(description: "terminal output updates")
        let token = bridge.addObserver(for: pane.id) { snapshot in
            if snapshot.renderedText.contains("hello from shell") {
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 2)
        bridge.removeObserver(for: pane.id, token: token)
    }

    func testTerminalPaneInputPreservesRightOptionAndCompositionPaths() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)

        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 19,
                key: "2",
                text: "@",
                modifiers: [.rightOption],
                phase: .keyDown,
                isRepeat: false,
                route: .terminal
            ),
            inPane: pane.id
        )

        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 33,
                key: "",
                text: nil,
                modifiers: [.rightOption],
                phase: .keyDown,
                isRepeat: false,
                route: .composition
            ),
            inPane: pane.id
        )

        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 14,
                key: "e",
                text: "é",
                modifiers: [],
                phase: .keyDown,
                isRepeat: false,
                route: .terminal
            ),
            inPane: pane.id
        )

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertTrue(snapshot.renderedText.contains("@é"))
    }
}
