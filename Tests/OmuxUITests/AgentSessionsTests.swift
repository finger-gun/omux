import XCTest

final class AgentSessionsTests: OmuxUITestsBase {
    // MARK: - Helpers

    private var toggleButton: XCUIElement {
        app.buttons[A11yID.vaultSidebarToggle.rawValue]
    }

    private var vaultSidebar: XCUIElement {
        app.groups[A11yID.vaultSidebar.rawValue]
    }

    /// Returns true when the sidebar is open and interactable.
    private var isSidebarOpen: Bool {
        vaultSidebar.exists && vaultSidebar.isHittable
    }

    /// Toggles the vault sidebar via the ⇧⌘B keyboard shortcut.
    ///
    /// The toggle button lives inside the native macOS title bar (y ≈ 24 pt on
    /// CI runners where the window sits at the top of the screen). XCUITest
    /// refuses to synthesize coordinate-based clicks into the system title bar
    /// region regardless of accessibility attributes, so direct `.click()` on
    /// the button is unreliable on CI. The keyboard shortcut is equivalent and
    /// works unconditionally.
    private func clickToggle() {
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("b", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// Waits up to `timeout` seconds for the sidebar to become open (hittable).
    @discardableResult
    private func waitForSidebarOpen(timeout: TimeInterval = 10) -> Bool {
        let pred = NSPredicate(format: "isHittable == true")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: vaultSidebar)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }

    /// Waits up to `timeout` seconds for the sidebar to become closed (not hittable).
    @discardableResult
    private func waitForSidebarClosed(timeout: TimeInterval = 10) -> Bool {
        let pred = NSPredicate(format: "isHittable == false")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: vaultSidebar)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }

    /// Closes the vault sidebar if it is currently open so each test starts
    /// from a known-closed state regardless of prior test execution order.
    private func closeSidebarIfOpen() {
        guard isSidebarOpen else { return }
        clickToggle()
        let waitResult = waitForSidebarClosed(timeout: 5)
        XCTAssertTrue(waitResult, "Sidebar did not close within timeout — test starting from an indeterminate state")
    }

    // MARK: - Tests

    func testToggleButtonExistsInTitleBar() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should be visible in the title bar"
        )
    }

    func testToggleButtonHasTooltip() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )
        XCTAssertEqual(
            toggleButton.label,
            "Toggle Agent Sessions",
            "Toggle button should have the correct accessibility label"
        )
    }

    func testToggleButtonOpensAgentSessionsSidebar() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )
        closeSidebarIfOpen()
        clickToggle()
        XCTAssertTrue(
            waitForSidebarOpen(),
            "Agent Sessions sidebar should appear after clicking the toggle button"
        )
    }

    func testToggleButtonClosesAgentSessionsSidebar() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )
        closeSidebarIfOpen()

        // Open.
        clickToggle()
        XCTAssertTrue(waitForSidebarOpen(), "Agent Sessions sidebar should open after first click")

        // Close.
        clickToggle()
        XCTAssertTrue(
            waitForSidebarClosed(),
            "Agent Sessions sidebar should close after clicking the toggle button again"
        )
    }

    func testToggleButtonRemainsVisibleWhenSidebarIsOpen() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )
        closeSidebarIfOpen()

        clickToggle()
        XCTAssertTrue(waitForSidebarOpen(), "Agent Sessions sidebar should open")
        XCTAssertTrue(
            toggleButton.exists,
            "Agent Sessions toggle button should remain visible in the title bar when the sidebar is open"
        )
    }

    func testToggleViaKeyboardShortcut() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )
        closeSidebarIfOpen()

        // Open via keyboard shortcut ⇧⌘B.
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForSidebarOpen(),
            "Agent Sessions sidebar should open via keyboard shortcut ⇧⌘B"
        )

        // Close via keyboard shortcut ⇧⌘B.
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForSidebarClosed(),
            "Agent Sessions sidebar should close via keyboard shortcut ⇧⌘B"
        )
    }
}
