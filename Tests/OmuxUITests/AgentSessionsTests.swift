import XCTest

final class AgentSessionsTests: OmuxUITestsBase {
    // MARK: - Helpers

    private var toggleButton: XCUIElement {
        app.buttons[A11yID.vaultSidebarToggle.rawValue]
    }

    private var vaultSidebar: XCUIElement {
        app.groups[A11yID.vaultSidebar.rawValue]
    }

    /// Closes the vault sidebar if it is currently open so each test starts
    /// from a known-closed state regardless of prior test execution order.
    private func closeSidebarIfOpen() {
        guard vaultSidebar.exists else { return }
        toggleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let hiddenPredicate = NSPredicate(format: "exists == false")
        _ = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: hiddenPredicate, object: vaultSidebar)],
            timeout: 3
        )
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

        // Ensure the sidebar is closed before starting.
        closeSidebarIfOpen()

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

        // Ensure the sidebar is closed before starting, then open it.
        closeSidebarIfOpen()
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

        // Ensure the sidebar is closed before starting so the test is
        // independent of whatever state prior tests left it in.
        if vaultSidebar.exists {
            toggleButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            let hiddenPredicate = NSPredicate(format: "exists == false")
            _ = XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: hiddenPredicate, object: vaultSidebar)],
                timeout: 3
            )
        }

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

        // Ensure the sidebar is closed before starting.
        closeSidebarIfOpen()

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
        // Ensure the sidebar is closed before starting.
        closeSidebarIfOpen()

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
