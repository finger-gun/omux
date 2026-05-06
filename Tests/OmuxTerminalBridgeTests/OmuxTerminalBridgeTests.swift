import AppKit
import CGhostty
import OmuxConfig
import OmuxTheme
import Foundation
import XCTest
@testable import OmuxCore
@testable import OmuxTerminalBridge

final class OmuxTerminalBridgeTests: XCTestCase {
    func testTerminalTextActivationExtractsTokenAtPointerLocation() {
        let paneID = PaneID()
        let request = TerminalTextActivationRequest(
            paneID: paneID,
            location: CGPoint(x: 40, y: 10),
            viewSize: CGSize(width: 320, height: 40),
            terminalSize: TerminalSize(columns: 40, rows: 2),
            modifiers: [.leftCommand]
        )

        let hit = TerminalTextActivationResolver.hit(
            in: "older line\nREADME.md docs/configuration.md",
            request: request
        )

        XCTAssertEqual(hit?.token, "README.md")
        XCTAssertEqual(hit?.row, 1)
    }

    func testTerminalTextActivationAllowsNearMissWithinSameLine() {
        let paneID = PaneID()
        let request = TerminalTextActivationRequest(
            paneID: paneID,
            location: CGPoint(x: 80, y: 10),
            viewSize: CGSize(width: 320, height: 40),
            terminalSize: TerminalSize(columns: 40, rows: 2),
            modifiers: [.leftCommand]
        )

        let hit = TerminalTextActivationResolver.hit(
            in: "older line\nREADME.md",
            request: request
        )

        XCTAssertEqual(hit?.token, "README.md")
        XCTAssertEqual(hit?.row, 1)
    }

    func testTerminalTextActivationSelectsPointedTokenInMultiColumnLsOutput() {
        let paneID = PaneID()
        let line = "AGENTS.md         LICENSE         README.md         Sources"
        let readmeColumn = line.distance(from: line.startIndex, to: line.range(of: "README.md")!.lowerBound) + 2
        let request = TerminalTextActivationRequest(
            paneID: paneID,
            location: CGPoint(x: CGFloat(readmeColumn * 10), y: 10),
            viewSize: CGSize(width: 800, height: 40),
            terminalSize: TerminalSize(columns: 80, rows: 2),
            modifiers: [.leftCommand]
        )

        let hit = TerminalTextActivationResolver.hit(
            in: "older line\n\(line)",
            request: request
        )

        XCTAssertEqual(hit?.token, "README.md")
    }

    func testTerminalTextActivationDoesNotGuessFirstTokenOnRowWhenPointerMisses() {
        let paneID = PaneID()
        let request = TerminalTextActivationRequest(
            paneID: paneID,
            location: CGPoint(x: 140, y: 10),
            viewSize: CGSize(width: 800, height: 40),
            terminalSize: TerminalSize(columns: 80, rows: 2),
            modifiers: [.leftCommand]
        )

        let hit = TerminalTextActivationResolver.hit(
            in: "older line\nAGENTS.md         README.md",
            request: request
        )

        XCTAssertNil(hit)
    }

    func testTerminalTextActivationExtractsFilenameFromLongLsOutput() {
        let paneID = PaneID()
        let line = "-rw-r--r--  1 lejahmie  staff  1200 May  6 10:00 README.md"
        let readmeColumn = line.distance(from: line.startIndex, to: line.range(of: "README.md")!.lowerBound) + 3
        let request = TerminalTextActivationRequest(
            paneID: paneID,
            location: CGPoint(x: CGFloat(readmeColumn * 10), y: 10),
            viewSize: CGSize(width: 800, height: 40),
            terminalSize: TerminalSize(columns: 80, rows: 2),
            modifiers: [.leftCommand]
        )

        let hit = TerminalTextActivationResolver.hit(
            in: "older line\n\(line)",
            request: request
        )

        XCTAssertEqual(hit?.token, "README.md")
    }

    func testTerminalTextActivationDoesNotFallbackAcrossLines() {
        let paneID = PaneID()
        let request = TerminalTextActivationRequest(
            paneID: paneID,
            location: CGPoint(x: 160, y: 10),
            viewSize: CGSize(width: 320, height: 60),
            terminalSize: TerminalSize(columns: 40, rows: 3),
            modifiers: [.leftCommand]
        )

        let hit = TerminalTextActivationResolver.hit(
            in: "README.md\n ",
            request: request
        )

        XCTAssertNil(hit)
    }

    func testTerminalTextActivationResolvesRelativePathFromWorkingDirectory() {
        XCTAssertEqual(
            TerminalTextActivationResolver.resolvedLocalPath(token: "README.md", cwd: "/repo"),
            "/repo/README.md"
        )
        XCTAssertEqual(
            TerminalTextActivationResolver.resolvedLocalPath(token: "docs/guide.md:42", cwd: "/repo"),
            "/repo/docs/guide.md"
        )
        XCTAssertNil(TerminalTextActivationResolver.resolvedLocalPath(token: "https://example.com", cwd: "/repo"))
    }

    func testBridgeOwnsSurfaceLifecycle() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
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

    func testBridgePreservesSessionEnvironmentOnAttach() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(
            shell: "/bin/sh",
            workingDirectory: "/tmp",
            environment: ["OMUX_RESTORE_SCROLLBACK_FILE": "/tmp/replay.ansi", "SHELL": "/bin/zsh"]
        )
        let pane = Pane(title: "Main", session: session)

        let attachment = try bridge.attach(session: session, to: pane)

        var expectedEnvironment = session.environment
        expectedEnvironment[OpenMUXTerminalEnvironment.paneIDKey] = pane.id.rawValue
        expectedEnvironment[OpenMUXTerminalEnvironment.sessionIDKey] = session.id.rawValue
        XCTAssertEqual(runtime.session(for: attachment.runtimeSurfaceID)?.environment, expectedEnvironment)
    }

    func testScrollbackReplayStoreWritesRawANSIReplayFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)
        let scrollback = PaneScrollbackSnapshot(text: "\u{001B}[31mred\u{001B}[0m\nplain", truncated: false)

        let replay = try XCTUnwrap(store.prepareReplay(for: scrollback))

        XCTAssertEqual(replay.environment[ScrollbackReplayStore.environmentKey], replay.fileURL.path)
        XCTAssertEqual(try String(contentsOf: replay.fileURL, encoding: .utf8), scrollback.text)
        let attributes = try FileManager.default.attributesOfItem(atPath: replay.fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testScrollbackReplayStoreSkipsEmptyReplayAndCleansStaleFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)

        XCTAssertNil(store.prepareReplay(for: PaneScrollbackSnapshot(text: "\n\n", truncated: false)))
        let stale = try XCTUnwrap(store.prepareReplay(for: PaneScrollbackSnapshot(text: "stale", truncated: false)))
        let fresh = try XCTUnwrap(store.prepareReplay(for: PaneScrollbackSnapshot(text: "fresh", truncated: false)))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: stale.fileURL.path
        )

        store.cleanupStaleFiles(olderThan: Date(timeIntervalSince1970: 2))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.fileURL.path))
    }

    func testScrollbackReplayStoreStripsUnsafeAlternateScreenSequences() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)
        let scrollback = PaneScrollbackSnapshot(
            text: "\u{001B}[?1049h\u{001B}[31mred\u{001B}[0m\u{001B}[?1049l",
            truncated: false
        )

        let replay = try XCTUnwrap(store.prepareReplay(for: scrollback))
        let replayText = try String(contentsOf: replay.fileURL, encoding: .utf8)

        XCTAssertFalse(replayText.contains("\u{001B}[?1049h"))
        XCTAssertFalse(replayText.contains("\u{001B}[?1049l"))
        XCTAssertTrue(replayText.contains("\u{001B}[31mred\u{001B}[0m"))
    }

    func testScrollbackReplayStoreDeduplicatesRepeatedTailPromptLines() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)
        let prompt = "project [\u{001B}[35mbranch-name\u{001B}[0m][$!?][tool v1]"
        let plainPrompt = "project [branch-name][$!?][tool v1]"
        let scrollback = PaneScrollbackSnapshot(
            text: """
            real output
            \(plainPrompt)
            \(plainPrompt)
            \(prompt)
            """,
            truncated: false
        )

        let replay = try XCTUnwrap(store.prepareReplay(for: scrollback))
        let replayText = try String(contentsOf: replay.fileURL, encoding: .utf8)

        XCTAssertEqual(replayText, "real output")
        XCTAssertFalse(replayText.contains("\u{001B}[35m"))
    }

    func testScrollbackReplayStoreDropsTrailingBracketedPromptVariants() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)
        let dirtyPrompt = "project [\u{001B}[35mbranch-name\u{001B}[0m][\u{001B}[35m$!\u{001B}[0m][tool v1]"
        let cleanPrompt = "project [\u{001B}[35mbranch-name\u{001B}[0m][\u{001B}[35m$\u{001B}[0m][tool v1]"
        let scrollback = PaneScrollbackSnapshot(
            text: "real output\r\n\(dirtyPrompt)\r\n\(cleanPrompt)\r\n",
            truncated: false
        )

        XCTAssertEqual(TerminalScrollbackTextSanitizer.sanitizedForReplayOrPersistence(scrollback.text), "real output")
        let replay = try XCTUnwrap(store.prepareReplay(for: scrollback))
        let replayText = try String(contentsOf: replay.fileURL, encoding: .utf8)

        XCTAssertEqual(replayText, "real output")
        XCTAssertFalse(replayText.contains("branch-name"))
    }

    func testScrollbackReplayStoreKeepsPlainRepeatedTailOutput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)
        let scrollback = PaneScrollbackSnapshot(text: "line\nsame\nsame\nsame", truncated: false)

        let replay = try XCTUnwrap(store.prepareReplay(for: scrollback))
        let replayText = try String(contentsOf: replay.fileURL, encoding: .utf8)

        XCTAssertEqual(replayText, scrollback.text)
    }

    func testScrollbackReplayStoreDeduplicatesPlainPromptAndLoginTailNoise() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)
        let prompt = "project [branch-name][$!?][tool v1]"
        let scrollback = PaneScrollbackSnapshot(
            text: """
            useful output
            Last login: Tue May 5 09:00:00 on ttys001
            \(prompt)
            Last login: Tue May 5 10:00:00 on ttys002
            \(prompt)
            """,
            truncated: false
        )

        let replay = try XCTUnwrap(store.prepareReplay(for: scrollback))
        let replayText = try String(contentsOf: replay.fileURL, encoding: .utf8)

        XCTAssertEqual(
            replayText,
            """
            useful output
            Last login: Tue May 5 10:00:00 on ttys002
            """
        )
    }

    func testScrollbackReplayStoreSkipsPromptOnlyReplay() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrollbackReplayStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrollbackReplayStore(directoryURL: root)
        let scrollback = PaneScrollbackSnapshot(
            text: "project [branch-name][$!?][tool v1]",
            truncated: false
        )

        XCTAssertNil(store.prepareReplay(for: scrollback))
    }

    func testScrollbackReplayWrapperPreparesShellQuotedLaunchSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scrollback Replay Wrapper Tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapperStore = ScrollbackReplayWrapperStore(directoryURL: root)
        let replay = TerminalScrollbackReplay(fileURL: root.appendingPathComponent("replay.ansi"))
        let baseSession = SessionDescriptor(
            shell: "/bin/zsh",
            workingDirectory: "/tmp/project",
            environment: ["EXISTING": "1", "SHELL": "/bin/bash"]
        )

        let launch = try XCTUnwrap(wrapperStore.prepareLaunch(baseSession: baseSession, replay: replay))

        XCTAssertEqual(launch.session.id, baseSession.id)
        XCTAssertEqual(launch.session.workingDirectory, "/tmp/project")
        XCTAssertEqual(launch.session.shell, "/bin/sh '\(launch.wrapperURL.path)'")
        XCTAssertFalse(launch.session.shell.contains("direct:"))
        XCTAssertEqual(launch.session.environment["EXISTING"], "1")
        XCTAssertEqual(launch.session.environment["SHELL"], "/bin/zsh")
        XCTAssertEqual(launch.session.environment[ScrollbackReplayStore.environmentKey], replay.fileURL.path)
        let script = try String(contentsOf: launch.wrapperURL, encoding: .utf8)
        XCTAssertTrue(script.contains("cat \"$OMUX_RESTORE_SCROLLBACK_FILE\""))
        XCTAssertTrue(script.contains("printf '\\033[0m'"))
        XCTAssertTrue(script.contains("printf '\\033[?25h'"))
        XCTAssertTrue(script.contains("exec \"${SHELL:-/bin/sh}\" -l"))
        let attributes = try FileManager.default.attributesOfItem(atPath: launch.wrapperURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
    }

    func testSurfaceCreationDoesNotHoldBridgeLockWhileRuntimeCreatesSurface() throws {
        let runtime = BlockingCreateSurfaceRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let existingPane = Pane(title: "Existing", session: SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp"))
        let newPane = Pane(title: "New", session: SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp"))

        _ = try bridge.createSurface(for: existingPane)
        runtime.blockingPaneID = newPane.id

        let createFinished = expectation(description: "surface creation finished")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try bridge.createSurface(for: newPane)
            } catch {
                XCTFail("surface creation failed: \(error)")
            }
            createFinished.fulfill()
        }

        XCTAssertTrue(runtime.waitForBlockedCreate(timeout: .now() + 1))

        let lookupFinished = expectation(description: "existing surface lookup finished")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertNotNil(bridge.surface(for: existingPane.id))
            lookupFinished.fulfill()
        }
        wait(for: [lookupFinished], timeout: 0.25)

        runtime.releaseBlockedCreate()
        wait(for: [createFinished], timeout: 1)
    }

    @MainActor
    func testBridgeCreatesHostedPaneViewForAttachedPane() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)

        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        hostedView.frame = NSRect(x: 0, y: 0, width: 800, height: 480)
        hostedView.layoutSubtreeIfNeeded()

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertGreaterThan(snapshot.columns, 20)
        XCTAssertGreaterThan(snapshot.rows, 5)
        XCTAssertTrue(hostedView.focusTarget === runtime.hostedViews["inspect:\(pane.id.rawValue)"])
    }

    @MainActor
    func testDefaultBridgeUsesRuntimeHostedSurfaceWhenGhosttyKitExists() throws {
        let bridge = GhosttyTerminalBridge()
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        let pane = Pane(title: "Ghostty", session: session)

        let surface = try bridge.createSurface(for: pane)
        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        hostedView.frame = NSRect(x: 0, y: 0, width: 800, height: 480)
        hostedView.layoutSubtreeIfNeeded()

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hasGhosttyKit = FileManager.default.fileExists(
            atPath: repositoryRoot
                .appendingPathComponent("Vendor/ghostty/macos/GhosttyKit.xcframework")
                .path
        )

        let runtimeContainer = try XCTUnwrap(hostedView.subviews.first)
        XCTAssertTrue(hasGhosttyKit)
        XCTAssertEqual(surface.runtimeSurfaceID, "cghostty:\(pane.id.rawValue)")
        XCTAssertTrue(hostedView.focusTarget is RuntimeTerminalHostView)
        XCTAssertTrue(runtimeContainer.subviews.contains { $0 === hostedView.focusTarget })
    }

    @MainActor
    func testRuntimeHostedPaneUsesRuntimeViewAsFocusTargetWithoutOverlay() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: false) { _ in }

        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        XCTAssertTrue(hostedView.focusTarget === runtimeView)

        let runtimeContainer = try XCTUnwrap(hostedView.subviews.first)
        XCTAssertEqual(runtimeContainer.subviews.count, 1)
        XCTAssertTrue(runtimeContainer.subviews.first === runtimeView)
    }

    func testBridgeFailsWhenRuntimeAttachCannotRecover() throws {
        let runtime = InspectableGhosttyRuntime()
        runtime.attachFailuresRemaining = 3
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        XCTAssertThrowsError(try bridge.attach(session: session, to: pane))
        XCTAssertEqual(runtime.attachAttempts, 3)
    }

    func testBridgeRetriesTransientRuntimeAttachBeforeFailing() throws {
        let runtime = InspectableGhosttyRuntime()
        runtime.attachFailuresRemaining = 2
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)

        XCTAssertEqual(runtime.attachAttempts, 3)
        XCTAssertEqual(bridge.snapshot(for: pane.id)?.textUnavailableReason, "history unavailable")
    }

    @MainActor
    func testRuntimeHostedViewFocusHandoffKeepsMouseDownEvent() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)
        var focusedPaneID: PaneID?

        _ = try bridge.attach(session: session, to: pane)
        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: false) { paneID in
            focusedPaneID = paneID
        }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostedView
        hostedView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 640, height: 480)
        runtimeView.frame = hostedView.bounds

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 24, y: 32),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        runtimeView.mouseDown(with: event)

        XCTAssertEqual(focusedPaneID, pane.id)
        XCTAssertEqual(runtime.mouseEventOrder, ["pos", "button"])
        XCTAssertEqual(runtime.mousePositions.first?.point, CGPoint(x: 24, y: 32))
        XCTAssertEqual(runtime.mouseButtons.count, 1)
        XCTAssertEqual(runtime.mouseButtons.first?.state, GHOSTTY_MOUSE_PRESS)
        XCTAssertEqual(runtime.mouseButtons.first?.buttonNumber, 0)
    }

    @MainActor
    func testRuntimeHostedViewClaimsCommandClickActivation() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)
        var activationRequest: TerminalTextActivationRequest?

        _ = try bridge.attach(session: session, to: pane)
        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: true, onFocus: { _ in }) { request in
            activationRequest = request
            return true
        }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostedView
        hostedView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 640, height: 480)
        runtimeView.frame = hostedView.bounds

        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 24, y: 32),
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        runtimeView.mouseDown(with: mouseDown)

        XCTAssertEqual(activationRequest?.paneID, pane.id)
        XCTAssertEqual(runtime.mouseButtons.count, 0)
        XCTAssertEqual(runtime.mousePositions.count, 0)
    }

    @MainActor
    func testRuntimeHostedViewForwardsUnhandledCommandClick() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: true, onFocus: { _ in }) { _ in false }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostedView
        hostedView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 640, height: 480)
        runtimeView.frame = hostedView.bounds

        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 24, y: 32),
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        runtimeView.mouseDown(with: mouseDown)

        XCTAssertEqual(runtime.mouseButtons.count, 1)
        XCTAssertEqual(runtime.mousePositions.count, 1)
    }

    @MainActor
    func testRuntimeHostedViewShowsTextActivationCursorOnCommandHover() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)
        var hoverRequest: TerminalTextActivationRequest?

        _ = try bridge.attach(session: session, to: pane)
        let hostedView = bridge.makeHostedPaneView(
            for: pane,
            isFocused: true,
            onFocus: { _ in },
            onTextActivation: { _ in false },
            onTextActivationHover: { request in
                hoverRequest = request
                return true
            }
        )
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostedView
        hostedView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 640, height: 480)
        runtimeView.frame = hostedView.bounds

        let commandHover = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: NSPoint(x: 24, y: 32),
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 0,
            pressure: 0
        ))
        runtimeView.mouseMoved(with: commandHover)

        XCTAssertEqual(hoverRequest?.paneID, pane.id)
        XCTAssertTrue(runtimeView.isTextActivationCursorActive)

        let normalHover = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: NSPoint(x: 24, y: 32),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 0,
            pressure: 0
        ))
        runtimeView.mouseMoved(with: normalHover)

        XCTAssertFalse(runtimeView.isTextActivationCursorActive)
    }

    @MainActor
    func testRuntimeHostedViewReleasesStaleMouseButtonsBeforeHoverMoves() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        runtimeView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        runtimeView.pressedMouseButtonsProvider = { 0 }

        let mouseDown = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 24, y: 32),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        runtimeView.mouseDown(with: mouseDown)

        let moved = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: NSPoint(x: 40, y: 60),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 0,
                pressure: 0
            )
        )
        runtimeView.mouseMoved(with: moved)

        XCTAssertEqual(runtime.mouseButtons.count, 2)
        XCTAssertEqual(runtime.mouseButtons.first?.state, GHOSTTY_MOUSE_PRESS)
        XCTAssertEqual(runtime.mouseButtons.last?.state, GHOSTTY_MOUSE_RELEASE)
        XCTAssertEqual(runtime.mouseButtons.last?.buttonNumber, 0)
        XCTAssertEqual(runtime.mousePositions.last?.point, CGPoint(x: 40, y: 60))
    }

    @MainActor
    func testRuntimeHostedViewDoesNotClearMousePositionWhenDragExitsViewport() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        runtimeView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        runtimeView.pressedMouseButtonsProvider = { 1 }

        let mouseDown = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 24, y: 32),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        runtimeView.mouseDown(with: mouseDown)

        let exited = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: NSPoint(x: 400, y: 260),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 0,
                pressure: 0
            )
        )
        runtimeView.mouseExited(with: exited)

        XCTAssertFalse(runtime.mousePositions.contains { $0.point == nil })
    }

    @MainActor
    func testRuntimeHostedViewTrackingAreaDoesNotReceiveCrossPaneDragEvents() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        runtimeView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

        runtimeView.updateTrackingAreas()

        let trackingArea = try XCTUnwrap(runtimeView.trackingAreas.first)
        XCTAssertFalse(trackingArea.options.contains(.enabledDuringMouseDrag))
        XCTAssertTrue(trackingArea.options.contains(.mouseMoved))
        XCTAssertTrue(trackingArea.options.contains(.mouseEnteredAndExited))
    }

    @MainActor
    func testRuntimeHostedViewRoutesStandardEditCommandsThroughRuntimeActions() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        runtimeView.copy(nil)
        runtimeView.paste(nil)
        runtimeView.selectAll(nil)

        XCTAssertEqual(
            runtime.bindingActions,
            ["copy_to_clipboard", "paste_from_clipboard", "select_all"]
        )
    }

    @MainActor
    func testRuntimeHostedViewPastesDroppedFilePathsAsText() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        XCTAssertTrue(runtimeView.insertDroppedFileURLs([
            URL(fileURLWithPath: "/Users/me/Desktop/Screenshot 2026-05-01.png"),
        ]))

        XCTAssertEqual(runtime.committedTexts, ["'/Users/me/Desktop/Screenshot 2026-05-01.png'"])
    }

    func testDroppedFilePathTextIsShellQuoted() {
        let pasteText = TerminalDroppedFileText.pasteText(for: [
            URL(fileURLWithPath: "/tmp/plain.txt"),
            URL(fileURLWithPath: "/tmp/has space/it's.png"),
        ])

        XCTAssertEqual(pasteText, "'/tmp/plain.txt' '/tmp/has space/it'\\''s.png'")
    }

    @MainActor
    func testRuntimeHostedViewForwardsCommandArrowToGhosttySemantics() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        runtimeView.keyDown(with: try makeKeyEvent(keyCode: 123, characters: "", modifiers: .command))
        runtimeView.keyDown(with: try makeKeyEvent(keyCode: 124, characters: "", modifiers: .command))

        XCTAssertEqual(runtime.handledEvents.map(\.keyCode), [123, 124])
        XCTAssertEqual(runtime.handledEvents.map(\.modifiers), [[.leftCommand], [.leftCommand]])
        XCTAssertTrue(runtime.committedTexts.isEmpty)
        XCTAssertTrue(runtime.accumulatedEvents.isEmpty)
    }

    @MainActor
    func testRuntimeHostedViewKeepsExplicitOpenMUXShortcutsOutOfTerminalInput() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        runtimeView.keyDown(with: try makeKeyEvent(keyCode: 2, characters: "d", modifiers: .command))

        XCTAssertTrue(runtime.committedTexts.isEmpty)
        XCTAssertTrue(runtime.handledEvents.isEmpty)
        XCTAssertTrue(runtime.accumulatedEvents.isEmpty)
    }

    @MainActor
    func testRuntimeHostedViewForwardsUnknownCommandChordToGhosttySemantics() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        runtimeView.keyDown(with: try makeKeyEvent(keyCode: 0, characters: "a", modifiers: .command))

        let event = try XCTUnwrap(runtime.handledEvents.last)
        XCTAssertEqual(event.keyCode, 0)
        XCTAssertTrue(event.modifiers.contains(.leftCommand))
        XCTAssertEqual(event.route, .terminal)
    }

    @MainActor
    func testRuntimeHostedViewForwardsModifiedBackspaceToGhosttySemantics() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        runtimeView.keyDown(
            with: try makeKeyEvent(
                keyCode: 51,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}",
                modifiers: .command
            )
        )
        runtimeView.keyDown(
            with: try makeKeyEvent(
                keyCode: 51,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}",
                modifiers: .option
            )
        )

        XCTAssertEqual(runtime.handledEvents.map(\.keyCode), [51, 51])
        XCTAssertTrue(runtime.handledEvents[0].modifiers.contains(.leftCommand))
        XCTAssertTrue(runtime.handledEvents[1].modifiers.contains(.leftOption))
        XCTAssertTrue(runtime.committedTexts.isEmpty)
    }

    @MainActor
    func testRuntimeHostedViewForwardsTextCommandSelectorDuringInterpretation() throws {
        let runtimeView = TextCommandRuntimeSurfaceView(
            selector: #selector(NSResponder.deleteWordBackward(_:))
        )
        var handledEvents: [NormalizedKeyEvent] = []
        runtimeView.normalizedKeyHandler = { event in
            handledEvents.append(event)
        }

        runtimeView.keyDown(
            with: try makeKeyEvent(
                keyCode: 51,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}",
                modifiers: .option
            )
        )

        XCTAssertEqual(handledEvents.count, 1)
        XCTAssertEqual(handledEvents.first?.keyCode, 51)
        XCTAssertTrue(handledEvents.first?.modifiers.contains(.leftOption) == true)
    }

    @MainActor
    func testRuntimeHostedViewDoesNotDuplicateTextCommandFallbackEvents() throws {
        let runtimeView = TextCommandRuntimeSurfaceView(
            selector: #selector(NSResponder.deleteToBeginningOfLine(_:))
        )
        var handledEvents: [NormalizedKeyEvent] = []
        runtimeView.normalizedKeyHandler = { event in
            handledEvents.append(event)
        }

        runtimeView.keyDown(
            with: try makeKeyEvent(
                keyCode: 51,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}",
                modifiers: .command
            )
        )

        XCTAssertEqual(handledEvents.count, 1)
        XCTAssertEqual(handledEvents.first?.keyCode, 51)
        XCTAssertTrue(handledEvents.first?.modifiers.contains(.leftCommand) == true)
    }

    func testBridgeIgnoresExplicitOpenMUXShortcutsRatherThanSynthesizingTerminalInput() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)

        try bridge.handle(
            NormalizedKeyEvent(
                keyCode: 2,
                key: "d",
                text: "d",
                modifiers: [.leftCommand],
                phase: .keyDown,
                isRepeat: false,
                route: .shortcut
            ),
            inPane: pane.id
        )

        XCTAssertTrue(runtime.handledEvents.isEmpty)
        XCTAssertTrue(runtime.sentTexts.isEmpty)
    }

    @MainActor
    func testRuntimeHostedViewTracksPointerScrollAndPressureEvents() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        runtimeView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        runtimeView.pressedMouseButtonsProvider = { 0 }

        let moved = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: NSPoint(x: 40, y: 60),
                modifierFlags: [.option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 0,
                pressure: 0
            )
        )
        runtimeView.mouseMoved(with: moved)
        runtimeView.mouseExited(with: moved)

        runtimeView.mouseScrollHandler?(3.5, -7.0, true, .changed)

        runtimeView.mousePressureHandler?(2, 0.75)

        XCTAssertEqual(runtime.mousePositions.count, 2)
        XCTAssertEqual(runtime.mousePositions.first?.point, CGPoint(x: 40, y: 60))
        XCTAssertNil(runtime.mousePositions.last?.point)
        XCTAssertEqual(runtime.mouseScrolls.count, 1)
        XCTAssertEqual(runtime.mouseScrolls.first?.x, 3.5)
        XCTAssertEqual(runtime.mouseScrolls.first?.y, -7.0)
        XCTAssertEqual(runtime.mouseScrolls.first?.precise, true)
        XCTAssertEqual(runtime.mouseScrolls.first?.momentum, .changed)
        XCTAssertEqual(runtime.mousePressures.count, 1)
        XCTAssertEqual(runtime.mousePressures.first?.stage, 2)
        XCTAssertEqual(runtime.mousePressures.first?.pressure, 0.75)
    }

    @MainActor
    func testHostedRuntimeClipboardReadsStandardPasteboardText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString("runtime paste", forType: .string)

        let result = HostedRuntimeClipboard.readString(for: GHOSTTY_CLIPBOARD_STANDARD) { location in
            guard location == GHOSTTY_CLIPBOARD_STANDARD else { return nil }
            return pasteboard
        }

        XCTAssertEqual(result, "runtime paste")
    }

    @MainActor
    func testCGhosttyRuntimeClipboardCallbacksResolveSurfaceUserdata() throws {
        let runtime = CGhosttyRuntime()
        let paneID = PaneID(rawValue: "clipboard-callback")
        let runtimeSurfaceID = try runtime.createSurface(for: paneID)
        let hostedView = try XCTUnwrap(
            runtime.makeHostedSurfaceView(for: paneID, runtimeSurfaceID: runtimeSurfaceID)
        )

        let context = try XCTUnwrap(
            HostedRuntimeClipboard.callbackContext(
                fromSurfaceUserdata: Unmanaged.passUnretained(hostedView).toOpaque()
            )
        )

        XCTAssertTrue(context.runtime === runtime)
        XCTAssertEqual(context.runtimeSurfaceID, runtimeSurfaceID)
    }

    @MainActor
    func testHostedRuntimeClipboardWritesTextPlainContentToStandardPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()

        let textPlain = Array("copied from runtime".utf8CString)
        let mime = Array("text/plain".utf8CString)
        mime.withUnsafeBufferPointer { mimeBuffer in
            textPlain.withUnsafeBufferPointer { textBuffer in
                var content = ghostty_clipboard_content_s(
                    mime: mimeBuffer.baseAddress,
                    data: textBuffer.baseAddress
                )

                withUnsafePointer(to: &content) { pointer in
                    let buffer = UnsafeBufferPointer(start: pointer, count: 1)
                    HostedRuntimeClipboard.write(buffer, for: GHOSTTY_CLIPBOARD_STANDARD) { location in
                        guard location == GHOSTTY_CLIPBOARD_STANDARD else { return nil }
                        return pasteboard
                    }
                }
            }
        }

        XCTAssertEqual(pasteboard.string(forType: .string), "copied from runtime")
    }

    @MainActor
    func testHostedRuntimeClipboardRejectsSelectionClipboardOnMacOS() {
        let selectionRead = HostedRuntimeClipboard.readString(for: GHOSTTY_CLIPBOARD_SELECTION) { _ in
            XCTFail("selection clipboard should not request a pasteboard")
            return nil
        }

        XCTAssertNil(selectionRead)
    }

    @MainActor
    func testRuntimeHostedViewPublishesPreeditAndCommitThroughTextInputClient() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        runtimeView.setMarkedText("¨", selectedRange: NSRange(), replacementRange: NSRange())
        runtimeView.insertText("é", replacementRange: NSRange())

        XCTAssertEqual(runtime.preeditUpdates, ["¨", nil])
        XCTAssertEqual(runtime.committedTexts, ["é"])
    }

    @MainActor
    func testRuntimeHostedViewExposesRuntimeSelectionToAppKitQueries() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeSurfaceID = "inspect:\(pane.id.rawValue)"
        let runtimeView = try XCTUnwrap(runtime.hostedViews[runtimeSurfaceID])
        runtime.selectionsBySurface[runtimeSurfaceID] = RuntimeTerminalSelection(
            text: "selected terminal text",
            offset: 4,
            length: 22
        )

        var actualRange = NSRange()
        let attributed = runtimeView.attributedSubstring(
            forProposedRange: NSRange(location: 4, length: 22),
            actualRange: &actualRange
        )

        XCTAssertEqual(runtimeView.selectedRange(), NSRange(location: 4, length: 22))
        XCTAssertEqual(attributed?.string, "selected terminal text")
        XCTAssertEqual(actualRange, NSRange(location: 4, length: 22))
        XCTAssertEqual(bridge.selection(forPane: pane.id)?.text, "selected terminal text")
    }

    @MainActor
    func testRuntimeHostedViewCancelsPreeditWithoutCommittedText() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        runtimeView.setMarkedText("^", selectedRange: NSRange(), replacementRange: NSRange())
        runtimeView.unmarkText()

        XCTAssertEqual(runtime.preeditUpdates, ["^", nil])
        XCTAssertTrue(runtime.committedTexts.isEmpty)
    }

    @MainActor
    func testRuntimeHostedViewUsesTranslatedModifiersOnlyForTextGeneration() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        runtimeView.translatedKeyEventProvider = { event in
            NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: [],
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: []) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option, NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK))],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "∂",
                charactersIgnoringModifiers: "d",
                isARepeat: false,
                keyCode: 2
            )
        )

        runtimeView.keyDown(with: event)

        let handledEvent = try XCTUnwrap(runtime.accumulatedEvents.first)
        XCTAssertTrue(handledEvent.modifiers.contains(.rightOption))
        XCTAssertEqual(handledEvent.text, "d")
    }

    @MainActor
    func testRuntimeHostedViewSupportsLeftOptionAltTranslationFixture() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])
        runtimeView.translatedKeyEventProvider = { event in
            NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: [],
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: []) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "@",
                charactersIgnoringModifiers: "2",
                isARepeat: false,
                keyCode: 19
            )
        )

        runtimeView.keyDown(with: event)

        let handledEvent = try XCTUnwrap(runtime.accumulatedEvents.last)
        XCTAssertTrue(handledEvent.modifiers.contains(.leftOption))
        XCTAssertEqual(handledEvent.text, "2")
    }

    @MainActor
    func testRuntimeHostedViewForwardsInjectedLayoutTextWithoutHardcodedMap() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        let fixture = "ß"
        runtimeView.translatedKeyEventProvider = { event in
            NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: fixture,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: fixture,
                charactersIgnoringModifiers: "s",
                isARepeat: false,
                keyCode: 1
            )
        )

        runtimeView.keyDown(with: event)

        XCTAssertEqual(runtime.accumulatedEvents.last?.text, fixture)
    }

    @MainActor
    func testRuntimeHostedViewPreservesSwedishIsoLeftOptionFixtureWhenRightActsAsAlt() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)
        _ = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let runtimeView = try XCTUnwrap(runtime.hostedViews["inspect:\(pane.id.rawValue)"])

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "@",
                charactersIgnoringModifiers: "2",
                isARepeat: false,
                keyCode: 19
            )
        )

        runtimeView.keyDown(with: event)

        let handledEvent = try XCTUnwrap(runtime.accumulatedEvents.last)
        XCTAssertTrue(handledEvent.modifiers.contains(.leftOption))
        XCTAssertEqual(handledEvent.text, "@")
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

    func testTerminalBridgeDoesNotLoadUserGhosttyDefaults() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeSourcesURL = repositoryRoot.appending(path: "Sources/OmuxTerminalBridge")
        let enumerator = FileManager.default.enumerator(
            at: bridgeSourcesURL,
            includingPropertiesForKeys: nil
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else {
                continue
            }

            let contents = try String(contentsOf: fileURL)
            XCTAssertFalse(
                contents.contains("ghostty_config_load_default_files"),
                "Bridge must not read user Ghostty defaults in \(fileURL.path)"
            )
        }
    }

    func testApplyCompiledConfigUsesGeneratedThemeValues() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }

        let theme = makeTheme(name: "bridge")
        let compiler = OmuxThemeCompiler(
            buildVersion: "test-build",
            generatedGhosttyDirectoryURL: directory
        )
        let output = compiler.compile(theme: theme, config: OmuxConfig.defaults)
        let fileURL = try compiler.write(output: output)

        _ = try bridge.applyCompiledConfig(path: fileURL)

        XCTAssertEqual(runtime.visibleBackground, theme.tokens[.backgroundCanvas]?.hexString)
        XCTAssertEqual(runtime.visibleForeground, theme.tokens[.foregroundPrimary]?.hexString)
        XCTAssertEqual(runtime.visiblePalette[0], theme.tokens[.ansiBlack]?.hexString)
        XCTAssertEqual(runtime.visiblePalette[15], theme.tokens[.ansiBrightWhite]?.hexString)
    }

    func testRefreshCompiledConfigKeepsRunningSessionAlive() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }

        _ = try bridge.attach(session: session, to: pane)
        let compiler = OmuxThemeCompiler(
            buildVersion: "test-build",
            generatedGhosttyDirectoryURL: directory
        )
        let output = compiler.compile(theme: makeTheme(name: "refresh"), config: OmuxConfig.defaults)
        let fileURL = try compiler.write(output: output)

        _ = try bridge.refreshCompiledConfig(path: fileURL)

        XCTAssertTrue(runtime.ownsSession(for: "inspect:\(pane.id.rawValue)"))
        XCTAssertEqual(bridge.attachedSession(for: pane.id), session.id)
        XCTAssertNotNil(bridge.snapshot(for: pane.id))
    }

    func testBuiltInThemesDriveRuntimeBackgrounds() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let directory = try temporaryDirectory()
        defer { cleanup(directory) }

        let compiler = OmuxThemeCompiler(
            buildVersion: "test-build",
            generatedGhosttyDirectoryURL: directory
        )
        let (themes, diagnostics) = OmuxThemeRegistry().loadBuiltInThemes()
        XCTAssertFalse(diagnostics.contains(where: { $0.severity.isError }))

        for theme in themes {
            let output = compiler.compile(theme: theme, config: OmuxConfig.defaults)
            let fileURL = try compiler.write(output: output)
            _ = try bridge.applyCompiledConfig(path: fileURL)
            XCTAssertEqual(runtime.visibleBackground, theme.tokens[.backgroundCanvas]?.hexString, "theme \(theme.name)")
        }
    }

    func testTerminalPaneInputPreservesRightOptionAndCompositionPaths() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
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

        XCTAssertEqual(runtime.handledEvents.map(\.keyCode), [19, 33, 14, 36])
        XCTAssertEqual(runtime.handledEvents.map(\.text), ["@", nil, "é", "\r"])
    }

    func testResizeUpdatesSnapshotDimensions() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)
        try bridge.resize(paneID: pane.id, columns: 120, rows: 40)

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertEqual(snapshot.columns, 120)
        XCTAssertEqual(snapshot.rows, 40)
    }

    func testBridgeReturnsBoundedScrollbackSnapshot() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        let attachment = try bridge.attach(session: session, to: pane)
        runtime.scrollbackBySurface[attachment.runtimeSurfaceID] = "one\ntwo\nthree"

        let snapshot = try XCTUnwrap(bridge.scrollbackSnapshot(for: pane.id, maxBytes: 1_000, maxLines: 2))
        XCTAssertEqual(snapshot.text, "two\nthree")
        XCTAssertTrue(snapshot.truncated)
    }

    func testBridgeUsesStyledScrollbackSnapshotForReplayOnly() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        let attachment = try bridge.attach(session: session, to: pane)
        runtime.scrollbackBySurface[attachment.runtimeSurfaceID] = "red"
        runtime.styledScrollbackBySurface[attachment.runtimeSurfaceID] = "\u{001B}[31mred\u{001B}[0m"

        XCTAssertEqual(bridge.terminalTextSnapshot(for: pane.id).text, "red")
        XCTAssertEqual(bridge.scrollbackSnapshot(for: pane.id)?.text, "\u{001B}[31mred\u{001B}[0m")
    }

    func testBridgeReturnsByteBoundedScrollbackSnapshot() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        let attachment = try bridge.attach(session: session, to: pane)
        runtime.scrollbackBySurface[attachment.runtimeSurfaceID] = "abcdef"

        let snapshot = try XCTUnwrap(bridge.scrollbackSnapshot(for: pane.id, maxBytes: 3, maxLines: 100))
        XCTAssertEqual(snapshot.text, "def")
        XCTAssertTrue(snapshot.truncated)
    }

    func testBridgeReturnsAvailableEmptyTerminalTextSnapshot() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        let attachment = try bridge.attach(session: session, to: pane)
        runtime.scrollbackBySurface[attachment.runtimeSurfaceID] = ""

        let textSnapshot = bridge.terminalTextSnapshot(for: pane.id)
        XCTAssertTrue(textSnapshot.isAvailable)
        XCTAssertEqual(textSnapshot.text, "")
        XCTAssertNil(textSnapshot.unavailableReason)
        XCTAssertNil(bridge.scrollbackSnapshot(for: pane.id))
    }

    func testBridgeSessionSnapshotUsesBoundedRuntimeText() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        let attachment = try bridge.attach(session: session, to: pane)
        runtime.scrollbackBySurface[attachment.runtimeSurfaceID] = (1...4_500).map { "line-\($0)" }.joined(separator: "\n")

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertEqual(snapshot.transcript.split(separator: "\n").count, 4_000)
        XCTAssertEqual(snapshot.transcript.split(separator: "\n").first, "line-501")
        XCTAssertTrue(snapshot.textTruncated)
        XCTAssertNil(snapshot.textUnavailableReason)
        XCTAssertEqual(snapshot.shell, "/bin/sh")
        XCTAssertEqual(snapshot.workingDirectory, "/tmp")
    }

    func testBridgeReturnsNilWhenScrollbackUnavailable() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)

        XCTAssertNil(bridge.scrollbackSnapshot(for: pane.id))
        let textSnapshot = bridge.terminalTextSnapshot(for: pane.id)
        XCTAssertFalse(textSnapshot.isAvailable)
        XCTAssertEqual(textSnapshot.unavailableReason, "history unavailable")
    }

    func testBridgeReturnsNilWhenScrollbackSurfaceMissing() throws {
        let bridge = GhosttyTerminalBridge(runtime: InspectableGhosttyRuntime())

        XCTAssertNil(bridge.scrollbackSnapshot(for: PaneID(rawValue: "missing")))
    }

    func testBridgePublishesTypedTerminalActionEvents() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        let attachment = try bridge.attach(session: session, to: pane)
        let receivedEvent = LockedValue<TerminalActionEvent?>(nil)
        let token = bridge.addTerminalActionObserver { event in
            receivedEvent.value = event
        }

        runtime.emit(.workingDirectoryChanged("/var/tmp"), on: attachment.runtimeSurfaceID)

        XCTAssertEqual(receivedEvent.value?.paneID, pane.id)
        XCTAssertEqual(receivedEvent.value?.sessionID, session.id)
        XCTAssertEqual(receivedEvent.value?.runtimeSurfaceID, attachment.runtimeSurfaceID)
        XCTAssertEqual(receivedEvent.value?.action, .workingDirectoryChanged("/var/tmp"))
        XCTAssertEqual(receivedEvent.value?.payload.objectValue?["path"], .string("/var/tmp"))
        bridge.removeTerminalActionObserver(token: token)
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String? = nil,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    func testRuntimeOwnedRunSubmitsReturnButSendTextDoesNot() throws {
        let runtime = InspectableGhosttyRuntime()
        let bridge = GhosttyTerminalBridge(runtime: runtime)
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Runtime", session: session)

        _ = try bridge.attach(session: session, to: pane)

        try bridge.run(command: "echo hello", inPane: pane.id)
        try bridge.send(text: "draft text", toPane: pane.id)

        let runtimeSurfaceID = "inspect:\(pane.id.rawValue)"
        XCTAssertEqual(runtime.sentTextsBySurface[runtimeSurfaceID], ["echo hello", "draft text"])
        XCTAssertEqual(runtime.handledEventsBySurface[runtimeSurfaceID]?.count, 1)
        XCTAssertEqual(runtime.handledEventsBySurface[runtimeSurfaceID]?.first?.keyCode, 36)
        XCTAssertEqual(runtime.handledEventsBySurface[runtimeSurfaceID]?.first?.text, "\r")
    }
}

private final class InspectableGhosttyRuntime: GhosttyRuntime {
    enum AttachFailure: Error {
        case transient
    }

    private var sessions: [String: SessionDescriptor] = [:]
    private var terminalActionHandler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    var attachFailuresRemaining = 0
    private(set) var attachAttempts = 0
    private(set) var visibleBackground: String?
    private(set) var visibleForeground: String?
    private(set) var visiblePalette: [Int: String] = [:]
    private(set) var hostedViews: [String: InspectableRuntimeSurfaceView] = [:]
    private(set) var committedTexts: [String] = []
    private(set) var sentTexts: [String] = []
    private(set) var handledEvents: [NormalizedKeyEvent] = []
    private(set) var preeditUpdates: [String?] = []
    private(set) var accumulatedEvents: [NormalizedKeyEvent] = []
    private(set) var sentTextsBySurface: [String: [String]] = [:]
    private(set) var handledEventsBySurface: [String: [NormalizedKeyEvent]] = [:]
    private(set) var bindingActions: [String] = []
    private(set) var mouseButtons: [(state: ghostty_input_mouse_state_e, buttonNumber: Int, modifiers: KeyModifiers)] = []
    private(set) var mousePositions: [(point: CGPoint?, modifiers: KeyModifiers)] = []
    private(set) var mouseEventOrder: [String] = []
    private(set) var mouseScrolls: [(x: Double, y: Double, precise: Bool, momentum: NSEvent.Phase)] = []
    private(set) var mousePressures: [(stage: Int, pressure: Double)] = []
    var selectionsBySurface: [String: RuntimeTerminalSelection] = [:]
    var scrollbackBySurface: [String: String] = [:]
    var styledScrollbackBySurface: [String: String] = [:]

    func applyCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        try loadVisibleState(from: path)
        return []
    }

    func refreshCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic] {
        try loadVisibleState(from: path)
        return []
    }

    func createSurface(for paneID: PaneID) throws -> String {
        "inspect:\(paneID.rawValue)"
    }

    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        attachAttempts += 1
        if attachFailuresRemaining > 0 {
            attachFailuresRemaining -= 1
            throw AttachFailure.transient
        }

        sessions[runtimeSurfaceID] = session
    }

    func session(for runtimeSurfaceID: String) -> SessionDescriptor? {
        sessions[runtimeSurfaceID]
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        sessions.removeValue(forKey: runtimeSurfaceID)
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        if let existing = hostedViews[runtimeSurfaceID] {
            return existing
        }
        let view = InspectableRuntimeSurfaceView(frame: .zero)
        view.normalizedKeyHandler = { [weak self] event in
            self?.handledEvents.append(event)
        }
        view.committedTextHandler = { [weak self] text in
            self?.committedTexts.append(text)
        }
        view.accumulatedTextHandler = { [weak self] event, text in
            var accumulatedEvent = event
            accumulatedEvent.text = text
            self?.accumulatedEvents.append(accumulatedEvent)
        }
        view.preeditHandler = { [weak self] text in
            self?.preeditUpdates.append(text)
        }
        view.imeRectProvider = {
            NSRect(x: 10, y: 20, width: 0, height: 18)
        }
        view.copyHandler = { [weak self] in
            self?.bindingActions.append("copy_to_clipboard")
        }
        view.pasteHandler = { [weak self] in
            self?.bindingActions.append("paste_from_clipboard")
        }
        view.selectAllHandler = { [weak self] in
            self?.bindingActions.append("select_all")
        }
        view.mouseButtonHandler = { [weak self] state, buttonNumber, modifiers in
            self?.mouseEventOrder.append("button")
            self?.mouseButtons.append((state: state, buttonNumber: buttonNumber, modifiers: modifiers))
            return true
        }
        view.mousePositionHandler = { [weak self] point, modifiers in
            self?.mouseEventOrder.append("pos")
            self?.mousePositions.append((point: point, modifiers: modifiers))
        }
        view.mouseScrollHandler = { [weak self] x, y, precise, momentum in
            self?.mouseScrolls.append((x: x, y: y, precise: precise, momentum: momentum))
        }
        view.mousePressureHandler = { [weak self] stage, pressure in
            self?.mousePressures.append((stage: stage, pressure: pressure))
        }
        view.selectionProvider = { [weak self] in
            self?.selectionsBySurface[runtimeSurfaceID]
        }
        hostedViews[runtimeSurfaceID] = view
        return view
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        sessions[runtimeSurfaceID] != nil
    }

    func send(text: String, to runtimeSurfaceID: String) throws {
        sentTexts.append(text)
        sentTextsBySurface[runtimeSurfaceID, default: []].append(text)
    }

    func handle(_ event: NormalizedKeyEvent, on runtimeSurfaceID: String) throws {
        handledEvents.append(event)
        handledEventsBySurface[runtimeSurfaceID, default: []].append(event)
    }

    func selection(for runtimeSurfaceID: String) -> RuntimeTerminalSelection? {
        selectionsBySurface[runtimeSurfaceID]
    }

    func scrollbackSnapshot(runtimeSurfaceID: String, maxBytes: Int, maxLines: Int) -> PaneScrollbackSnapshot? {
        if let text = styledScrollbackBySurface[runtimeSurfaceID] {
            return PaneScrollbackSnapshot.bounded(
                text: text,
                maxBytes: maxBytes,
                maxLines: maxLines
            )
        }
        return terminalTextSnapshot(
            runtimeSurfaceID: runtimeSurfaceID,
            maxBytes: maxBytes,
            maxLines: maxLines
        ).scrollbackSnapshot
    }

    func terminalTextSnapshot(runtimeSurfaceID: String, maxBytes: Int, maxLines: Int) -> TerminalTextSnapshot {
        guard let text = scrollbackBySurface[runtimeSurfaceID] else {
            return .unavailable(reason: "history unavailable", maxBytes: maxBytes, maxLines: maxLines)
        }
        return TerminalTextSnapshot.bounded(
            text: text,
            maxBytes: maxBytes,
            maxLines: maxLines
        )
    }

    func resizeSurface(runtimeSurfaceID: String, columns: Int, rows: Int) throws {
        _ = runtimeSurfaceID
        _ = columns
        _ = rows
    }

    func setSurfaceFocused(runtimeSurfaceID: String, focused: Bool) {
        _ = runtimeSurfaceID
        _ = focused
    }

    func setTerminalActionHandler(
        _ handler: (@Sendable (RuntimeTerminalActionRecord) -> Bool)?
    ) {
        terminalActionHandler = handler
    }

    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        defaultSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        guard sessions[runtimeSurfaceID] != nil else {
            return nil
        }

        let textSnapshot = terminalTextSnapshot(
            runtimeSurfaceID: runtimeSurfaceID,
            maxBytes: PaneScrollbackSnapshot.defaultMaxBytes,
            maxLines: PaneScrollbackSnapshot.defaultMaxLines
        )
        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: runtimeSurfaceID,
            transcript: textSnapshot.text,
            currentInput: "",
            textUnavailableReason: textSnapshot.unavailableReason,
            textTruncated: textSnapshot.truncated,
            shell: descriptor.shell,
            workingDirectory: descriptor.workingDirectory,
            columns: defaultSize.columns,
            rows: defaultSize.rows
        )
    }

    func emit(_ action: TerminalAction, on runtimeSurfaceID: String) {
        _ = terminalActionHandler?(RuntimeTerminalActionRecord(runtimeSurfaceID: runtimeSurfaceID, action: action))
    }

    private func loadVisibleState(from path: URL) throws {
        let contents = try String(contentsOf: path, encoding: .utf8)
        visiblePalette = [:]
        for line in contents.split(separator: "\n") {
            if line.hasPrefix("background = ") {
                visibleBackground = String(line.replacingOccurrences(of: "background = ", with: ""))
            } else if line.hasPrefix("foreground = ") {
                visibleForeground = String(line.replacingOccurrences(of: "foreground = ", with: ""))
            } else if line.hasPrefix("palette = ") {
                let value = line.replacingOccurrences(of: "palette = ", with: "")
                let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2, let index = Int(parts[0]) {
                    visiblePalette[index] = parts[1]
                }
            }
        }
    }
}

private final class InspectableRuntimeSurfaceView: RuntimeTerminalHostView {}

private final class TextCommandRuntimeSurfaceView: RuntimeTerminalHostView {
    private let selector: Selector

    init(selector: Selector) {
        self.selector = selector
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func interpretKeyEvents(_ eventArray: [NSEvent]) {
        _ = eventArray
        doCommand(by: selector)
    }
}

private final class BlockingCreateSurfaceRuntime: GhosttyRuntime {
    private let lock = NSLock()
    private let blockedCreateStarted = DispatchSemaphore(value: 0)
    private let blockedCreateRelease = DispatchSemaphore(value: 0)
    private var storedBlockingPaneID: PaneID?

    var blockingPaneID: PaneID? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedBlockingPaneID
        }
        set {
            lock.lock()
            storedBlockingPaneID = newValue
            lock.unlock()
        }
    }

    func waitForBlockedCreate(timeout: DispatchTime) -> Bool {
        blockedCreateStarted.wait(timeout: timeout) == .success
    }

    func releaseBlockedCreate() {
        blockedCreateRelease.signal()
    }

    func createSurface(for paneID: PaneID) throws -> String {
        if paneID == blockingPaneID {
            blockedCreateStarted.signal()
            _ = blockedCreateRelease.wait(timeout: .now() + 2)
        }
        return "blocking:\(paneID.rawValue)"
    }

    func attach(session: SessionDescriptor, to runtimeSurfaceID: String) throws {
        _ = session
        _ = runtimeSurfaceID
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        _ = runtimeSurfaceID
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return nil
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private func makeTheme(name: String) -> OmuxTheme {
    let seed = deterministicThemeSeed(name: name, modulo: 160, offset: 40)
    let tokens = Dictionary(
        uniqueKeysWithValues: ThemeToken.allCases.map { token in
            let offset = UInt8(ThemeToken.allCases.firstIndex(of: token) ?? 0)
            return (
                token,
                ThemeColor(
                    red: seed &+ offset,
                    green: seed &+ 1 &+ offset,
                    blue: seed &+ 2 &+ offset
                )
            )
        }
    )
    return OmuxTheme(schema: 1, name: name, displayName: name.capitalized, tokens: tokens)
}

private func deterministicThemeSeed(name: String, modulo: UInt16, offset: UInt16) -> UInt8 {
    let hash = name.utf8.reduce(UInt32(2_166_136_261)) { partial, byte in
        (partial ^ UInt32(byte)) &* 16_777_619
    }
    return UInt8((hash % UInt32(modulo)) + UInt32(offset))
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
