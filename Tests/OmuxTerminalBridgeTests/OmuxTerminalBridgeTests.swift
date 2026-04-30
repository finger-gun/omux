import AppKit
import OmuxConfig
import OmuxTheme
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

    @MainActor
    func testBridgeCreatesHostedPaneViewForAttachedPane() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)

        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        hostedView.frame = NSRect(x: 0, y: 0, width: 800, height: 480)
        hostedView.layoutSubtreeIfNeeded()

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertGreaterThan(snapshot.columns, 20)
        XCTAssertGreaterThan(snapshot.rows, 5)
    }

    @MainActor
    func testHostedPaneViewRoutesKeyboardAndPasteToLiveSession() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)
        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        let focusTarget = try XCTUnwrap(hostedView.focusTarget as? NSTextView)

        let expectation = expectation(description: "hosted pane input reaches live session")
        expectation.assertForOverFulfill = false
        let token = bridge.addObserver(for: pane.id) { snapshot in
            if snapshot.renderedText.contains("hosted\n") {
                expectation.fulfill()
            }
        }

        for (text, keyCode) in [("e", UInt16(14)), ("c", UInt16(8)), ("h", UInt16(4)), ("o", UInt16(31)), (" ", UInt16(49)), ("h", UInt16(4)), ("o", UInt16(31)), ("s", UInt16(1)), ("t", UInt16(17)), ("e", UInt16(14)), ("d", UInt16(2))] {
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: text,
                    charactersIgnoringModifiers: text,
                    isARepeat: false,
                    keyCode: keyCode
                )
            )
            focusTarget.keyDown(with: event)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(" && printf '\\n'", forType: .string)
        focusTarget.paste(nil)

        let returnEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )
        focusTarget.keyDown(with: returnEvent)

        waitForExpectations(timeout: 3)
        bridge.removeObserver(for: pane.id, token: token)
    }

    @MainActor
    func testDefaultBridgeUsesRuntimeHostedSurfaceWhenGhosttyKitExists() throws {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        {
            throw XCTSkip("Embedded Ghostty runtime is disabled under xctest.")
        }

        let bridge = GhosttyTerminalBridge()
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        let pane = Pane(title: "Ghostty", session: session)

        let attachment = try bridge.attach(session: session, to: pane)
        let hostedView = bridge.makeHostedPaneView(for: pane, isFocused: true) { _ in }
        hostedView.frame = NSRect(x: 0, y: 0, width: 800, height: 480)
        hostedView.layoutSubtreeIfNeeded()

        let snapshot = try XCTUnwrap(bridge.snapshot(for: pane.id))
        XCTAssertGreaterThan(snapshot.columns, 0)
        XCTAssertGreaterThan(snapshot.rows, 0)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hasGhosttyKit = FileManager.default.fileExists(
            atPath: repositoryRoot
                .appendingPathComponent("Vendor/ghostty/macos/GhosttyKit.xcframework")
                .path
        )

        let runtimeContainer = try XCTUnwrap(hostedView.subviews.first)
        let childTypeNames = runtimeContainer.subviews.map { String(describing: type(of: $0)) }
        if hasGhosttyKit {
            XCTAssertEqual(attachment.runtimeSurfaceID, "cghostty:\(pane.id.rawValue)")
            XCTAssertTrue(childTypeNames.contains("GhosttyHostedSurfaceView"))
        } else {
            XCTAssertTrue(childTypeNames.contains("NSScrollView"))
        }
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

    @MainActor
    func testTerminalSessionSnapshotsUpdateWhenCommandRuns() throws {
        let bridge = GhosttyTerminalBridge(runtime: UnavailableGhosttyRuntime())
        let session = SessionDescriptor(shell: "/bin/sh", workingDirectory: "/tmp")
        let pane = Pane(title: "Main", session: session)

        _ = try bridge.attach(session: session, to: pane)
        try bridge.run(command: "printf 'hello from shell'", inPane: pane.id)

        let expectation = expectation(description: "terminal output updates")
        expectation.assertForOverFulfill = false
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

private final class InspectableGhosttyRuntime: GhosttyRuntime {
    private var sessions: [String: SessionDescriptor] = [:]
    private(set) var visibleBackground: String?
    private(set) var visibleForeground: String?
    private(set) var visiblePalette: [Int: String] = [:]

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
        sessions[runtimeSurfaceID] = session
    }

    func destroySurface(runtimeSurfaceID: String) throws {
        sessions.removeValue(forKey: runtimeSurfaceID)
    }

    @MainActor
    func makeHostedSurfaceView(for paneID: PaneID, runtimeSurfaceID: String) -> NSView? {
        _ = paneID
        _ = runtimeSurfaceID
        return NSView(frame: .zero)
    }

    func ownsSession(for runtimeSurfaceID: String) -> Bool {
        sessions[runtimeSurfaceID] != nil
    }

    func send(text: String, to runtimeSurfaceID: String) throws {
        _ = text
        _ = runtimeSurfaceID
    }

    func handle(_ event: NormalizedKeyEvent, on runtimeSurfaceID: String) throws {
        _ = event
        _ = runtimeSurfaceID
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

    func snapshot(
        paneID: PaneID,
        sessionID: SessionID,
        descriptor: SessionDescriptor,
        runtimeSurfaceID: String,
        fallbackSize: TerminalSize
    ) -> TerminalSessionSnapshot? {
        guard sessions[runtimeSurfaceID] != nil else {
            return nil
        }

        return TerminalSessionSnapshot(
            paneID: paneID,
            sessionID: sessionID,
            runtimeSurfaceID: runtimeSurfaceID,
            transcript: "runtime session",
            currentInput: "",
            shell: descriptor.shell,
            workingDirectory: descriptor.workingDirectory,
            columns: fallbackSize.columns,
            rows: fallbackSize.rows
        )
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

private func makeTheme(name: String) -> OmuxTheme {
    let seed = UInt8(abs(name.hashValue) % 160 + 40)
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

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
