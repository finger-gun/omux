import AppKit
import XCTest
@testable import OmuxCore

final class OmuxCoreTests: XCTestCase {
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

    func testUnknownCommandChordRemainsTerminalInput() {
        let raw = RawKeyInput(
            keyCode: 0,
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifiers: [.leftCommand]
        )

        let event = DefaultKeyEventNormalizer().normalize(raw)

        XCTAssertEqual(event.route, .terminal)
        XCTAssertTrue(event.modifiers.contains(.leftCommand))
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
