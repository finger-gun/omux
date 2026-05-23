import XCTest
@testable import OmuxCLI

final class TerminalInteractivePickerEngineTests: XCTestCase {
    func testEngineHandlesNavigationAndSearchKeys() throws {
        let driver = FakeTerminalInteractivePickerDriver(keys: [.down, .character("a"), .enter])
        let engine = TerminalInteractivePickerEngine<String>(
            allItems: ["north", "azure", "amber"],
            initialSelectedIndex: 0,
            filterItems: { items, query in
                guard query.isEmpty == false else { return items }
                return items.filter { $0.contains(query) }
            },
            renderLines: { state in
                ["items=\(state.items.count)", "query=\(state.searchQuery)"]
            },
            driver: driver
        )

        let selection = try engine.select()

        XCTAssertEqual(selection, "azure")
        XCTAssertEqual(driver.cursorVisibilityChanges, [false, true])
    }

    func testEngineRestoresTerminalOnCancel() throws {
        let driver = FakeTerminalInteractivePickerDriver(keys: [.cancel])
        let engine = TerminalInteractivePickerEngine<String>(
            allItems: ["one"],
            initialSelectedIndex: 0,
            filterItems: { items, _ in items },
            renderLines: { _ in ["line"] },
            driver: driver
        )

        let selection = try engine.select()

        XCTAssertNil(selection)
        XCTAssertEqual(driver.cursorVisibilityChanges, [false, true])
        XCTAssertEqual(driver.clearedLineCounts, [1])
    }

    func testEngineRestoresTerminalWhenRawModeThrowsAfterBody() {
        let driver = FakeTerminalInteractivePickerDriver(keys: [.enter], throwAfterBody: true)
        let engine = TerminalInteractivePickerEngine<String>(
            allItems: ["one"],
            initialSelectedIndex: 0,
            filterItems: { items, _ in items },
            renderLines: { _ in ["line"] },
            driver: driver
        )

        XCTAssertThrowsError(try engine.select())
        XCTAssertEqual(driver.cursorVisibilityChanges, [false, true])
        XCTAssertEqual(driver.clearedLineCounts, [1])
    }
}

private final class FakeTerminalInteractivePickerDriver: TerminalInteractivePickerDriver {
    private var keys: [TerminalInteractivePickerKey]
    private let throwAfterBody: Bool
    var cursorVisibilityChanges: [Bool] = []
    var clearedLineCounts: [Int] = []

    init(keys: [TerminalInteractivePickerKey], throwAfterBody: Bool = false) {
        self.keys = keys
        self.throwAfterBody = throwAfterBody
    }

    func isAvailable() -> Bool { true }

    func withRawMode<Result>(_ body: () throws -> Result) throws -> Result {
        let result = try body()
        if throwAfterBody {
            throw FakeError.afterBody
        }
        return result
    }

    func readKey() -> TerminalInteractivePickerKey {
        if keys.isEmpty {
            return .cancel
        }
        return keys.removeFirst()
    }

    func terminalRowCount() -> Int { 24 }

    func draw(lines: [String], previousLineCount _: Int) -> Int {
        lines.count
    }

    func clearRenderedLines(_ lineCount: Int) {
        clearedLineCounts.append(lineCount)
    }

    func setCursorVisible(_ isVisible: Bool) {
        cursorVisibilityChanges.append(isVisible)
    }

    private enum FakeError: Error {
        case afterBody
    }
}
