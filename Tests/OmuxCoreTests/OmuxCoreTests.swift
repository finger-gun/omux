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

    func testCommandChordRoutesToShortcut() {
        let raw = RawKeyInput(
            keyCode: 0,
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifiers: [.leftCommand]
        )

        let event = DefaultKeyEventNormalizer().normalize(raw)

        XCTAssertEqual(event.route, .shortcut)
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
    }

    func testClosingLastPaneTabInStackIsRejected() {
        let pane = Pane(
            title: "one",
            session: SessionDescriptor(shell: "/bin/zsh", workingDirectory: "/tmp")
        )
        var tab = Tab(title: "Main", panes: [pane], focusedPaneID: pane.id)

        XCTAssertNil(tab.closeFocusedPane())
    }
}
