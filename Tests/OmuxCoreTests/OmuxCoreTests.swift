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
}
