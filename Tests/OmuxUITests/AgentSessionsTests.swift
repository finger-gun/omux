import XCTest

final class AgentSessionsTests: OmuxUITestsBase {
    // MARK: - Helpers

    private var toggleButton: XCUIElement {
        app.buttons[A11yID.vaultSidebarToggle.rawValue]
    }

    private var vaultSidebar: XCUIElement {
        app.groups[A11yID.vaultSidebar.rawValue]
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
            toggleButton.value(forKey: "toolTip") as? String,
            "Toggle Agent Sessions (⇧⌘B)",
            "Toggle button should have the correct tooltip including the keyboard shortcut"
        )
    }

    func testToggleButtonOpensAgentSessionsSidebar() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )

        // The vault sidebar should not be visible initially.
        let hiddenPredicate = NSPredicate(format: "exists == false")
        let initiallyHidden = XCTNSPredicateExpectation(predicate: hiddenPredicate, object: vaultSidebar)
        XCTAssertEqual(
            XCTWaiter.wait(for: [initiallyHidden], timeout: 3),
            .completed,
            "Agent Sessions sidebar should be hidden on launch"
        )

        // Click the toggle button to open the sidebar.
        toggleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let visiblePredicate = NSPredicate(format: "exists == true")
        let sidebarVisible = XCTNSPredicateExpectation(predicate: visiblePredicate, object: vaultSidebar)
        XCTAssertEqual(
            XCTWaiter.wait(for: [sidebarVisible], timeout: 3),
            .completed,
            "Agent Sessions sidebar should appear after clicking the toggle button"
        )
    }

    func testToggleButtonClosesAgentSessionsSidebar() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )

        // Open the sidebar first.
        toggleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            vaultSidebar.waitForExistence(timeout: 3),
            "Agent Sessions sidebar should open after first click"
        )

        // Click again to close.
        toggleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let hiddenPredicate = NSPredicate(format: "exists == false")
        let sidebarHidden = XCTNSPredicateExpectation(predicate: hiddenPredicate, object: vaultSidebar)
        XCTAssertEqual(
            XCTWaiter.wait(for: [sidebarHidden], timeout: 3),
            .completed,
            "Agent Sessions sidebar should close after clicking the toggle button again"
        )
    }

    func testToggleButtonRemainsVisibleWhenSidebarIsOpen() {
        XCTAssertTrue(
            toggleButton.waitForExistence(timeout: 5),
            "Agent Sessions toggle button should exist"
        )

        // Open the sidebar.
        toggleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            vaultSidebar.waitForExistence(timeout: 3),
            "Agent Sessions sidebar should open"
        )

        // The toggle button should remain in the title bar while the sidebar is open.
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

        // Open via keyboard shortcut Cmd+Shift+B.
        app.typeKey("b", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            vaultSidebar.waitForExistence(timeout: 3),
            "Agent Sessions sidebar should open via keyboard shortcut ⇧⌘B"
        )

        // Close via keyboard shortcut again.
        app.typeKey("b", modifierFlags: [.command, .shift])

        let hiddenPredicate = NSPredicate(format: "exists == false")
        let sidebarHidden = XCTNSPredicateExpectation(predicate: hiddenPredicate, object: vaultSidebar)
        XCTAssertEqual(
            XCTWaiter.wait(for: [sidebarHidden], timeout: 3),
            .completed,
            "Agent Sessions sidebar should close via keyboard shortcut ⇧⌘B"
        )
    }

    func testToggleViaViewMenu() {
        // Open via View menu.
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Toggle Agent Sessions"].click()

        XCTAssertTrue(
            vaultSidebar.waitForExistence(timeout: 3),
            "Agent Sessions sidebar should open via View menu"
        )

        // Close via View menu.
        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Toggle Agent Sessions"].click()

        let hiddenPredicate = NSPredicate(format: "exists == false")
        let sidebarHidden = XCTNSPredicateExpectation(predicate: hiddenPredicate, object: vaultSidebar)
        XCTAssertEqual(
            XCTWaiter.wait(for: [sidebarHidden], timeout: 3),
            .completed,
            "Agent Sessions sidebar should close via View menu"
        )
    }
}
