import AppKit
import XCTest
@testable import OmuxCore

final class OmuxCoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OpenMUXShortcutClassifier.updateKeyBindings(.defaults)
    }

    func testRightOptionPreservesInternationalInput() {
        let raw = RawKeyInput(
            keyCode: 19,
            characters: "@",
            charactersIgnoringModifiers: "2",
            modifiers: [.rightOption],
            isComposing: false
        )

        let event = DefaultKeyEventNormalizer().normalize(raw)

        XCTAssertEqual(event.text, "@")
        XCTAssertTrue(event.modifiers.contains(.rightOption))
        XCTAssertEqual(event.route, .terminal)
    }

    func testSemanticVersionComparison() {
        XCTAssertLessThan(
            OpenMUXSemanticVersion(parsing: "0.4.0")!,
            OpenMUXSemanticVersion(parsing: "0.5.0")!
        )
        XCTAssertLessThan(
            OpenMUXSemanticVersion(parsing: "v0.5.0")!,
            OpenMUXSemanticVersion(parsing: "1.0.0")!
        )
    }

    func testVersionProviderReadsRepositoryVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "9.8.7\n".write(to: root.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        let executableURL = root.appendingPathComponent("bin/omux", isDirectory: false)
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: executableURL, atomically: true, encoding: .utf8)

        let provider = OpenMUXVersionProvider(
            executablePath: executableURL.path,
            currentDirectoryPath: root.appendingPathComponent("nested").path
        )

        XCTAssertEqual(try provider.currentVersion(), "9.8.7")
    }

    func testScrollbackSnapshotCombinedDeduplicatesOverlappingSurfaceAndActiveText() {
        let history = PaneScrollbackSnapshot(text: "first\nprompt\ncontinued", truncated: false)
        let active = PaneScrollbackSnapshot(text: "prompt\ncontinued", truncated: false)

        let combined = PaneScrollbackSnapshot.combined(history, active)

        XCTAssertEqual(combined?.text, "first\nprompt\ncontinued")
    }

    func testScrollbackSnapshotCombinedKeepsNonOverlappingText() {
        let history = PaneScrollbackSnapshot(text: "first\nsecond", truncated: false)
        let active = PaneScrollbackSnapshot(text: "third", truncated: false)

        let combined = PaneScrollbackSnapshot.combined(history, active)

        XCTAssertEqual(combined?.text, "first\nsecond\nthird")
    }

    func testReleaseMetadataParserFindsRequiredAssets() throws {
        let data = Data("""
        {
          "tag_name": "v0.5.0",
          "prerelease": false,
          "assets": [
            {
              "name": "OpenMUX-0.5.0-macos-unsigned.zip",
              "browser_download_url": "https://example.test/OpenMUX.zip",
              "size": 123
            },
            {
              "name": "checksums.txt",
              "browser_download_url": "https://example.test/checksums.txt"
            }
          ]
        }
        """.utf8)

        let release = try OpenMUXReleaseMetadataParser.parseLatestRelease(data: data)

        XCTAssertEqual(release.version.description, "0.5.0")
        XCTAssertEqual(release.appArchiveAsset?.name, "OpenMUX-0.5.0-macos-unsigned.zip")
        XCTAssertEqual(release.checksumAsset?.name, "checksums.txt")
    }

    func testDeadKeyRoutesToComposition() {
        let raw = RawKeyInput(
            keyCode: 33,
            characters: "",
            charactersIgnoringModifiers: "",
            modifiers: [.rightOption],
            isComposing: true
        )

        let event = DefaultKeyEventNormalizer().normalize(raw)

        XCTAssertNil(event.text)
        XCTAssertEqual(event.route, .composition)
    }

    func testExplicitOpenMUXCommandChordRoutesToShortcut() {
        let raw = RawKeyInput(
            keyCode: 2,
            characters: "d",
            charactersIgnoringModifiers: "d",
            modifiers: [.leftCommand]
        )

        let event = DefaultKeyEventNormalizer().normalize(raw)

        XCTAssertEqual(event.route, .shortcut)
    }

    func testPaneTabCommandChordsRouteToShortcut() {
        let commandT = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 17,
                characters: "t",
                charactersIgnoringModifiers: "t",
                modifiers: [.leftCommand]
            )
        )
        let commandW = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 13,
                characters: "w",
                charactersIgnoringModifiers: "w",
                modifiers: [.leftCommand]
            )
        )

        XCTAssertEqual(commandT.route, .shortcut)
        XCTAssertEqual(commandW.route, .shortcut)
    }

    func testScopedStructuralCommandShiftChordsRouteToShortcut() {
        let commandShiftW = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 13,
                characters: "W",
                charactersIgnoringModifiers: "w",
                modifiers: [.leftCommand, .leftShift]
            )
        )
        let commandShiftN = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 45,
                characters: "N",
                charactersIgnoringModifiers: "n",
                modifiers: [.leftCommand, .leftShift]
            )
        )
        let optionShiftN = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 45,
                characters: "N",
                charactersIgnoringModifiers: "n",
                modifiers: [.leftOption, .leftShift]
            )
        )

        XCTAssertEqual(commandShiftW.route, .shortcut)
        XCTAssertEqual(commandShiftN.route, .shortcut)
        XCTAssertEqual(optionShiftN.route, .terminal)
    }

    func testControlTabNavigationChordsRouteToShortcut() {
        let controlTab = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 48,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                modifiers: [.leftControl]
            )
        )
        let controlShiftTab = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 48,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                modifiers: [.leftControl, .leftShift]
            )
        )
        let optionTab = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 48,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                modifiers: [.leftOption]
            )
        )

        XCTAssertEqual(controlTab.route, .shortcut)
        XCTAssertEqual(controlShiftTab.route, .shortcut)
        XCTAssertEqual(optionTab.route, .terminal)
    }

    func testSplitResizeChordsRouteToShortcut() {
        let commandControlEqual = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 24,
                characters: "=",
                charactersIgnoringModifiers: "=",
                modifiers: [.leftCommand, .leftControl]
            )
        )
        let commandControlLeft = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 123,
                characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                charactersIgnoringModifiers: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                modifiers: [.leftCommand, .leftControl]
            )
        )
        let commandControlRight = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 124,
                characters: String(UnicodeScalar(NSRightArrowFunctionKey)!),
                charactersIgnoringModifiers: String(UnicodeScalar(NSRightArrowFunctionKey)!),
                modifiers: [.leftCommand, .leftControl]
            )
        )
        let optionControlLeft = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 123,
                characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                charactersIgnoringModifiers: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                modifiers: [.leftOption, .leftControl]
            )
        )

        XCTAssertEqual(commandControlEqual.route, .shortcut)
        XCTAssertEqual(commandControlLeft.route, .shortcut)
        XCTAssertEqual(commandControlRight.route, .shortcut)
        XCTAssertEqual(optionControlLeft.route, .terminal)
    }

    func testWorkspaceMoveChordsRouteToShortcut() {
        let commandControlShiftUp = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 126,
                characters: String(UnicodeScalar(NSUpArrowFunctionKey)!),
                charactersIgnoringModifiers: String(UnicodeScalar(NSUpArrowFunctionKey)!),
                modifiers: [.leftCommand, .leftControl, .leftShift]
            )
        )
        let commandControlShiftDown = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 125,
                characters: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                modifiers: [.leftCommand, .leftControl, .leftShift]
            )
        )

        XCTAssertEqual(commandControlShiftUp.route, .shortcut)
        XCTAssertEqual(commandControlShiftDown.route, .shortcut)
    }

    func testUnknownCommandChordRemainsTerminalInput() {
        let commandA = RawKeyInput(
            keyCode: 0,
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifiers: [.leftCommand]
        )
        let commandShiftT = RawKeyInput(
            keyCode: 17,
            characters: "T",
            charactersIgnoringModifiers: "t",
            modifiers: [.leftCommand, .leftShift]
        )

        let event = DefaultKeyEventNormalizer().normalize(commandA)
        let removedPaneAddAlias = DefaultKeyEventNormalizer().normalize(commandShiftT)

        XCTAssertEqual(event.route, .terminal)
        XCTAssertTrue(event.modifiers.contains(.leftCommand))
        XCTAssertEqual(removedPaneAddAlias.route, .terminal)
    }

    func testModifiedBackspaceRemainsTerminalInput() {
        let commandBackspace = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 51,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}",
                modifiers: [.leftCommand]
            )
        )
        let optionBackspace = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 51,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}",
                modifiers: [.leftOption]
            )
        )

        XCTAssertEqual(commandBackspace.route, .terminal)
        XCTAssertEqual(optionBackspace.route, .terminal)
    }

    func testConfigurableKeyBindingsOverrideDefaultsAndUnbindChords() throws {
        let registry = OpenMUXKeyBindingRegistry.effective(overrides: [
            OpenMUXKeyBindingOverride(
                chord: try OpenMUXKeyChord(parsing: "cmd+shift+w"),
                action: nil
            ),
            OpenMUXKeyBindingOverride(
                chord: try OpenMUXKeyChord(parsing: "cmd+shift+p"),
                action: .paneRemove
            ),
        ])
        let normalizer = DefaultKeyEventNormalizer(keyBindingRegistry: registry)

        let unboundDefault = normalizer.normalize(
            RawKeyInput(
                keyCode: 13,
                characters: "W",
                charactersIgnoringModifiers: "w",
                modifiers: [.leftCommand, .leftShift]
            )
        )
        let rebound = normalizer.normalize(
            RawKeyInput(
                keyCode: 35,
                characters: "P",
                charactersIgnoringModifiers: "p",
                modifiers: [.leftCommand, .leftShift]
            )
        )
        let composing = normalizer.normalize(
            RawKeyInput(
                keyCode: 35,
                characters: "",
                charactersIgnoringModifiers: "p",
                modifiers: [.leftCommand, .leftShift],
                isComposing: true
            )
        )

        XCTAssertEqual(unboundDefault.route, .terminal)
        XCTAssertEqual(rebound.route, .shortcut)
        XCTAssertEqual(composing.route, .composition)
    }

    func testCommandPaletteDefaultShortcutsRouteToShortcutAndCanBeUnbound() throws {
        let normalizer = DefaultKeyEventNormalizer(keyBindingRegistry: .defaults)
        let commandK = normalizer.normalize(
            RawKeyInput(
                keyCode: 40,
                characters: "k",
                charactersIgnoringModifiers: "k",
                modifiers: [.leftCommand]
            )
        )
        let commandShiftP = normalizer.normalize(
            RawKeyInput(
                keyCode: 35,
                characters: "P",
                charactersIgnoringModifiers: "p",
                modifiers: [.leftCommand, .leftShift]
            )
        )
        let optionCommandK = normalizer.normalize(
            RawKeyInput(
                keyCode: 40,
                characters: "˚",
                charactersIgnoringModifiers: "k",
                modifiers: [.leftCommand, .leftOption]
            )
        )

        XCTAssertEqual(commandK.route, .shortcut)
        XCTAssertEqual(commandShiftP.route, .shortcut)
        XCTAssertEqual(optionCommandK.route, .terminal)

        let unbound = DefaultKeyEventNormalizer(keyBindingRegistry: .effective(overrides: [
            OpenMUXKeyBindingOverride(chord: try OpenMUXKeyChord(parsing: "cmd+k"), action: nil),
            OpenMUXKeyBindingOverride(chord: try OpenMUXKeyChord(parsing: "cmd+shift+p"), action: nil),
        ]))
        XCTAssertEqual(unbound.normalize(RawKeyInput(
            keyCode: 40,
            characters: "k",
            charactersIgnoringModifiers: "k",
            modifiers: [.leftCommand]
        )).route, .terminal)
        XCTAssertEqual(unbound.normalize(RawKeyInput(
            keyCode: 35,
            characters: "P",
            charactersIgnoringModifiers: "p",
            modifiers: [.leftCommand, .leftShift]
        )).route, .terminal)
    }

    func testCommandPaletteParsingAndRanking() {
        let workspaceQuery = CommandPaletteParsedQuery(rawText: " project")
        let commandQuery = CommandPaletteParsedQuery(rawText: ">split")
        let whitespacePrefixQuery = CommandPaletteParsedQuery(rawText: " >split")

        XCTAssertEqual(workspaceQuery.mode, .workspace)
        XCTAssertEqual(workspaceQuery.matchingText, " project")
        XCTAssertEqual(commandQuery.mode, .command)
        XCTAssertEqual(commandQuery.matchingText, "split")
        XCTAssertEqual(whitespacePrefixQuery.mode, .workspace)

        let first = WorkspaceID(rawValue: "first")
        let second = WorkspaceID(rawValue: "second")
        let workspaces = [
            CommandPaletteWorkspace(id: first, displayName: "API", path: "/tmp/project-api", visibleOrder: 0, isActive: true),
            CommandPaletteWorkspace(id: second, displayName: "Project", path: "/tmp/api", visibleOrder: 1, isActive: false),
        ]

        let workspaceResults = CommandPaletteSearch.workspaceResults(query: "project", workspaces: workspaces)

        XCTAssertEqual(workspaceResults.map(\.invocationTarget), [.workspace(second), .workspace(first)])

        let commandResults = CommandPaletteSearch.commandResults(query: "split", commands: [
            CommandPaletteCommand(
                id: "disabled",
                title: "Split Disabled",
                category: .action,
                matchText: "split disabled",
                isEnabled: false,
                disabledReason: "No pane",
                invocationTarget: .action(.paneSplitRight)
            ),
            CommandPaletteCommand(
                id: "hidden",
                title: "Split With Path",
                category: .cli,
                matchText: "split path",
                requiresArguments: true,
                hasSafeDefaultTarget: false,
                invocationTarget: .cliCommand("hidden")
            ),
        ])

        XCTAssertEqual(commandResults.map(\.id), ["disabled", "hidden"])
        XCTAssertFalse(commandResults[0].isEnabled)
        XCTAssertEqual(commandResults[0].disabledReason, "No pane")
        XCTAssertEqual(commandResults[1].invocationTarget, .cliCommand("hidden"))
    }

    func testPaletteRoutingDoesNotClaimCompositionOrRightOptionText() {
        let composingCommandP = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 35,
                characters: "",
                charactersIgnoringModifiers: "p",
                modifiers: [.leftCommand],
                isComposing: true
            )
        )
        let rightOptionP = DefaultKeyEventNormalizer().normalize(
            RawKeyInput(
                keyCode: 35,
                characters: "π",
                charactersIgnoringModifiers: "p",
                modifiers: [.rightOption]
            )
        )

        XCTAssertEqual(composingCommandP.route, .composition)
        XCTAssertEqual(rightOptionP.route, .terminal)
        XCTAssertEqual(rightOptionP.text, "π")
    }

    func testControlChordRemainsTerminalInput() {
        let raw = RawKeyInput(
            keyCode: 8,
            characters: "\u{03}",
            charactersIgnoringModifiers: "c",
            modifiers: [.leftControl]
        )

        let event = DefaultKeyEventNormalizer().normalize(raw)

        XCTAssertEqual(event.route, .terminal)
        XCTAssertTrue(event.modifiers.contains(.leftControl))
    }

    func testAppKitEventPreservesRightOptionIdentity() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option, NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK))],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "@",
                charactersIgnoringModifiers: "2",
                isARepeat: false,
                keyCode: 19
            )
        )

        let modifiers = KeyModifiers(appKitEvent: event)

        XCTAssertTrue(modifiers.contains(.rightOption))
        XCTAssertFalse(modifiers.contains(.leftOption))
        XCTAssertEqual(KeyEventPhase.appKitPhase(for: event), .keyDown)
    }

    func testAppKitFlagsChangedPreservesReleasedRightOptionIdentity() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 0x3D
            )
        )

        let modifiers = KeyModifiers(appKitEvent: event)

        XCTAssertTrue(modifiers.contains(.rightOption))
        XCTAssertEqual(KeyEventPhase.appKitPhase(for: event), .keyUp)
    }

    func testPaneStacksTrackFocusedLocalTabIndependently() {
        let firstPane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let secondPane = Pane(
            title: "two",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        var tab = Tab(title: "Main", panes: [firstPane], focusedPaneID: firstPane.id)

        XCTAssertTrue(tab.createPaneInFocusedStack(secondPane))
        XCTAssertEqual(tab.paneStacks.count, 1)
        XCTAssertEqual(tab.focusedPane?.id, secondPane.id)
        XCTAssertEqual(tab.focusedPaneStack?.focusedPaneID, secondPane.id)

        XCTAssertTrue(tab.focusPane(firstPane.id))
        XCTAssertEqual(tab.focusedPaneStack?.id, tab.paneStacks.first?.id)
        XCTAssertEqual(tab.focusedPaneStack?.focusedPaneID, firstPane.id)
    }

    func testPaneContentDistinguishesTerminalAndExtensionPanes() throws {
        let session = SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        let terminalPane = Pane(title: "terminal", session: session)
        let extensionDescriptor = ExtensionPaneDescriptor(
            pluginID: "dev.fingergun.markdown-preview",
            contentKind: .html,
            source: "/tmp/README.md",
            html: "<h1>README</h1>"
        )
        let extensionPane = Pane(title: "README Preview", extensionPane: extensionDescriptor)

        XCTAssertTrue(terminalPane.isTerminal)
        XCTAssertEqual(terminalPane.terminalSession?.id, session.id)
        XCTAssertNil(terminalPane.extensionPane)
        XCTAssertFalse(extensionPane.isTerminal)
        XCTAssertNil(extensionPane.terminalSession)
        XCTAssertEqual(extensionPane.extensionPane, extensionDescriptor)
    }

    func testExtensionPaneCanFocusAndSplitWithoutTerminalSession() {
        let terminalPane = Pane(
            title: "terminal",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let extensionPane = Pane(
            title: "README Preview",
            extensionPane: ExtensionPaneDescriptor(pluginID: "dev.fingergun.markdown-preview", source: "/tmp/README.md")
        )
        var tab = Tab(title: "Main", panes: [terminalPane], focusedPaneID: terminalPane.id)

        XCTAssertTrue(tab.splitFocusedPane(extensionPane, axis: .columns))
        XCTAssertEqual(tab.focusedPane?.id, extensionPane.id)
        XCTAssertNil(tab.focusedPane?.terminalSession)
        XCTAssertTrue(tab.focusPane(terminalPane.id))
        XCTAssertTrue(tab.focusPane(extensionPane.id))
        XCTAssertTrue(tab.rootLayout.containsSession(id: terminalPane.session.id))
        XCTAssertFalse(tab.rootLayout.containsSession(id: SessionID()))
    }

    func testWorkspaceFocusBySessionIgnoresExtensionPanes() {
        let terminalPane = Pane(
            title: "terminal",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let extensionPane = Pane(
            title: "README Preview",
            extensionPane: ExtensionPaneDescriptor(pluginID: "dev.fingergun.markdown-preview", source: "/tmp/README.md")
        )
        let tab = Tab(title: "Main", panes: [terminalPane, extensionPane], focusedPaneID: extensionPane.id)
        var workspace = Workspace(
            generatedName: "workspace",
            rootPath: "/tmp",
            tabs: [tab],
            focusedTabID: tab.id
        )

        XCTAssertTrue(workspace.focus(sessionID: terminalPane.session.id))
        XCTAssertEqual(workspace.focusedPane?.id, terminalPane.id)
        XCTAssertFalse(workspace.focus(sessionID: SessionID()))
        XCTAssertEqual(workspace.focusedPane?.id, terminalPane.id)
    }

    func testPaneCodableDecodesLegacyTerminalShapeAndPreservesExtensionContent() throws {
        let legacyData = Data("""
        {
          "id": "pane-legacy",
          "title": "legacy",
          "session": {
            "id": "session-legacy",
            "shell": "/bin/zsh",
            "workingDirectory": "/tmp",
            "environment": {}
          },
          "terminalState": {}
        }
        """.utf8)

        let decodedLegacy = try JSONDecoder().decode(Pane.self, from: legacyData)
        XCTAssertEqual(decodedLegacy.terminalSession?.id.rawValue, "session-legacy")

        let extensionPane = Pane(
            id: PaneID(rawValue: "pane-preview"),
            title: "README Preview",
            extensionPane: ExtensionPaneDescriptor(
                pluginID: "dev.fingergun.markdown-preview",
                contentKind: .html,
                source: "/tmp/README.md",
                html: "<h1>README</h1>"
            )
        )
        let encoded = try JSONEncoder().encode(extensionPane)
        let decodedExtension = try JSONDecoder().decode(Pane.self, from: encoded)

        XCTAssertEqual(decodedExtension.extensionPane?.pluginID, "dev.fingergun.markdown-preview")
        XCTAssertEqual(decodedExtension.extensionPane?.contentKind, .html)
        XCTAssertNil(decodedExtension.terminalSession)
    }

    func testSplittingFocusedLocalTabCreatesSiblingPaneStack() {
        let firstPane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let secondPane = Pane(
            title: "two",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        var tab = Tab(title: "Main", panes: [firstPane], focusedPaneID: firstPane.id)

        XCTAssertTrue(tab.splitFocusedPane(secondPane, axis: .rows))
        XCTAssertEqual(tab.paneStacks.count, 2)
        XCTAssertEqual(tab.focusedPane?.id, secondPane.id)

        guard case .split(axis: .rows, proportions: let proportions, children: let children) = tab.rootLayout else {
            return XCTFail("expected root layout to become a split")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(proportions, [0.5, 0.5])
    }

    func testSplitProportionsNormalizeWhenUpdated() {
        let firstPane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let secondPane = Pane(
            title: "two",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        var tab = Tab(title: "Main", panes: [firstPane], focusedPaneID: firstPane.id)

        XCTAssertTrue(tab.splitFocusedPane(secondPane, axis: .columns))
        XCTAssertTrue(tab.updateSplitProportions([7, 3], forChildPaneIDs: [firstPane.id, secondPane.id]))

        guard case .split(axis: .columns, proportions: let proportions, children: let children) = tab.rootLayout else {
            return XCTFail("expected root layout to remain a split")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(proportions[0], 0.7, accuracy: 0.0001)
        XCTAssertEqual(proportions[1], 0.3, accuracy: 0.0001)
    }

    func testFocusedSplitCanResizeAndEqualizeWithKeyboardStep() {
        let firstPane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let secondPane = Pane(
            title: "two",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        var tab = Tab(title: "Main", panes: [firstPane], focusedPaneID: firstPane.id)

        XCTAssertTrue(tab.splitFocusedPane(secondPane, axis: .columns))
        XCTAssertTrue(tab.canResizeFocusedSplit(.left))
        XCTAssertTrue(tab.resizeFocusedSplit(.left))

        guard case .split(axis: .columns, proportions: let resizedProportions, children: let children) = tab.rootLayout else {
            return XCTFail("expected root layout to remain a split")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(resizedProportions[0], 0.45, accuracy: 0.0001)
        XCTAssertEqual(resizedProportions[1], 0.55, accuracy: 0.0001)

        XCTAssertTrue(tab.equalizeSplits())
        guard case .split(axis: .columns, proportions: let equalizedProportions, children: _) = tab.rootLayout else {
            return XCTFail("expected equalized layout to remain a split")
        }
        XCTAssertEqual(equalizedProportions[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(equalizedProportions[1], 0.5, accuracy: 0.0001)
    }

    func testClosingLastPaneTabInStackIsRejected() {
        let pane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        var tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)

        XCTAssertNil(tab.closeFocusedPane())
    }

    func testTabLayoutNodeCodableRoundTripPreservesSplitProportions() throws {
        let firstPane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let secondPane = Pane(
            title: "two",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        let node = TabLayoutNode.split(
            axis: .rows,
            proportions: [0.65, 0.35],
            children: [
                .paneStack(PaneStack(panes: [firstPane], focusedPaneID: firstPane.id)),
                .paneStack(PaneStack(panes: [secondPane], focusedPaneID: secondPane.id)),
            ]
        )

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(TabLayoutNode.self, from: data)

        guard case .split(axis: .rows, proportions: let proportions, children: let children) = decoded else {
            return XCTFail("expected split node after decoding")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(proportions[0], 0.65, accuracy: 0.0001)
        XCTAssertEqual(proportions[1], 0.35, accuracy: 0.0001)
    }

    func testPaneScrollbackSnapshotBoundsByLinesAndBytes() throws {
        let lineBounded = try XCTUnwrap(PaneScrollbackSnapshot.bounded(
            text: "one\ntwo\nthree",
            maxBytes: 1_000,
            maxLines: 2
        ))
        XCTAssertEqual(lineBounded.text, "two\nthree")
        XCTAssertTrue(lineBounded.truncated)

        let byteBounded = try XCTUnwrap(PaneScrollbackSnapshot.bounded(
            text: "abcdef",
            maxBytes: 3,
            maxLines: 10
        ))
        XCTAssertEqual(byteBounded.text, "def")
        XCTAssertTrue(byteBounded.truncated)
        XCTAssertNil(PaneScrollbackSnapshot.bounded(text: "\n\n"))
    }

    func testOmuxValuePreservesStructuredPayloadShape() throws {
        let value: OmuxValue = .object([
            "path": .string("/tmp/project"),
            "exitCode": .integer(1),
            "duration": .double(1.5),
            "healthy": .bool(false),
            "items": .array([.string("one"), .null]),
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(OmuxValue.self, from: data)

        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.objectValue?["exitCode"]?.integerValue, 1)
        XCTAssertEqual(decoded.objectValue?["items"]?.arrayValue?.count, 2)
    }
}
