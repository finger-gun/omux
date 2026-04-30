import Foundation
import XCTest
@testable import OmuxCore
@testable import OmuxTerminalBridge

final class OmuxTerminalBridgeTests: XCTestCase {
    func testBridgeOwnsSurfaceLifecycle() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
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
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)
        try bridge.run(command: "printf 'hello from shell'", inPane: pane.id)

        let expectation = expectation(description: "terminal output updates")
        let token = bridge.addObserver(for: pane.id) { snapshot in
            if snapshot.renderedText.contains("hello from shell") {
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: pane.id, token: token)
    }

    func testTerminalPaneInputPreservesRightOptionAndCompositionPaths() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
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

        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 36,
                key: "\r",
                text: "\r",
                modifiers: [],
                phase: .keyDown,
                isRepeat: false,
                route: .terminal
            ),
            inPane: pane.id
        )

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertEqual(snapshot.currentInput, "")
    }

    @MainActor
    func testRunCommandUsesPersistentInteractiveSession() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)

        let expectation = expectation(description: "working directory persists across commands")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: pane.id) { snapshot in
            if snapshot.renderedText.contains("/\n") {
                expectation.fulfill()
            }
        }

        try bridge.run(command: "cd /", inPane: pane.id)
        try bridge.run(command: "pwd", inPane: pane.id)

        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: pane.id, token: token)
    }

    func testResizeUpdatesSnapshotDimensions() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)
        try bridge.resize(paneID: pane.id, columns: 120, rows: 40)

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertEqual(snapshot.columns, 120)
        XCTAssertEqual(snapshot.rows, 40)
    }

    @MainActor
    func testDirectInputAndDeleteEditTheLiveShellCommand() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)

        let expectation = expectation(description: "edited command executes in live session")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: pane.id) { snapshot in
            if snapshot.renderedText.contains("hello\n") {
                expectation.fulfill()
            }
        }

        for text in ["e", "c", "h", "X"] {
            try bridge.handle(
                NormalizedKeyEvent(
                    keyCode: nil,
                    key: text,
                    text: text,
                    modifiers: [],
                    phase: .keyDown,
                    isRepeat: false,
                    route: .terminal
                ),
                inPane: pane.id
            )
        }

        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 51,
                key: "\u{7F}",
                text: nil,
                modifiers: [],
                phase: .keyDown,
                isRepeat: false,
                route: .terminal
            ),
            inPane: pane.id
        )

        for text in ["o", " hello"] {
            try bridge.handle(
                NormalizedKeyEvent(
                    keyCode: nil,
                    key: text,
                    text: text,
                    modifiers: [],
                    phase: .keyDown,
                    isRepeat: false,
                    route: .terminal
                ),
                inPane: pane.id
            )
        }

        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 36,
                key: "\r",
                text: "\r",
                modifiers: [],
                phase: .keyDown,
                isRepeat: false,
                route: .terminal
            ),
            inPane: pane.id
        )

        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: pane.id, token: token)
    }

    @MainActor
    func testPasteStyleTextInjectionTargetsLiveSession() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)

        let expectation = expectation(description: "paste text enters live session")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: pane.id) { snapshot in
            if snapshot.renderedText.contains("pasted\n") {
                expectation.fulfill()
            }
        }

        try bridge.send(text: "printf 'pasted' && printf '\\n'", toPane: pane.id)
        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 36,
                key: "\r",
                text: "\r",
                modifiers: [],
                phase: .keyDown,
                isRepeat: false,
                route: .terminal
            ),
            inPane: pane.id
        )

        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: pane.id, token: token)
    }
}
