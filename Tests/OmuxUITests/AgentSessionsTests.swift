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

    /// Clicks the toggle button using the element tap (not coordinate-based).
    /// Sleeps before the click to ensure the app is fully settled from any
    /// prior interaction (important on slow CI runners where layout animations
    /// may still be in-flight when the predicate fires), and after the click
    /// to allow the sidebar animation to complete before the next assertion.
    private func clickToggle() {
        Thread.sleep(forTimeInterval: 0.5)
        toggleButton.click()
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
        waitForSidebarClosed(timeout: 5)
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

    func testToggleViaViewMenu() {
        closeSidebarIfOpen()

        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Toggle Agent Sessions"].click()
        XCTAssertTrue(
            waitForSidebarOpen(),
            "Agent Sessions sidebar should open via View menu"
        )

        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Toggle Agent Sessions"].click()
        XCTAssertTrue(
            waitForSidebarClosed(),
            "Agent Sessions sidebar should close via View menu"
        )
    }
}
