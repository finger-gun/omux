import XCTest

// UI tests for the right sidebar (worktrees + agent sessions) and its
// per-widget toggle controls introduced in this branch.

final class RightSidebarTests: OmuxUITestsBase {

    // MARK: - Helpers

    private var vaultSidebar: XCUIElement {
        app.groups[A11yID.vaultSidebar.rawValue]
    }

    private var isSidebarOpen: Bool {
        vaultSidebar.exists && vaultSidebar.isHittable
    }

    /// Toggles the **whole** right sidebar via the new Alt+Cmd+B shortcut
    /// ("Toggle Right Sidebar" in the View menu).
    private func toggleRightSidebar() {
        app.typeKey("b", modifierFlags: [.command, .option])
    }

    /// Toggles the agent sessions widget via the existing ⇧⌘B shortcut.
    private func toggleAgentSessions() {
        app.typeKey("b", modifierFlags: [.command, .shift])
    }

    @discardableResult
    private func waitForSidebarOpen(timeout: TimeInterval = 10) -> Bool {
        let pred = NSPredicate(format: "isHittable == true")
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: pred, object: vaultSidebar)],
            timeout: timeout
        ) == .completed
    }

    @discardableResult
    private func waitForSidebarClosed(timeout: TimeInterval = 10) -> Bool {
        let pred = NSPredicate(format: "isHittable == false")
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: pred, object: vaultSidebar)],
            timeout: timeout
        ) == .completed
    }

    /// Ensures the sidebar is closed before each test so tests are order-independent.
    private func ensureSidebarClosed() {
        guard isSidebarOpen else { return }
        toggleRightSidebar()
        XCTAssertTrue(waitForSidebarClosed(timeout: 5), "Sidebar should have closed")
    }

    /// Ensures the sidebar is open before tests that need it.
    private func ensureSidebarOpen() {
        guard !isSidebarOpen else { return }
        toggleRightSidebar()
        XCTAssertTrue(waitForSidebarOpen(timeout: 5), "Sidebar should have opened")
    }

    // MARK: - Toggle Right Sidebar (Alt+Cmd+B)

    func testToggleRightSidebarOpensWhenClosed() {
        ensureSidebarClosed()
        toggleRightSidebar()
        XCTAssertTrue(
            waitForSidebarOpen(),
            "Right sidebar should open after Alt+Cmd+B when it was closed"
        )
    }

    func testToggleRightSidebarClosesWhenOpen() {
        ensureSidebarOpen()
        toggleRightSidebar()
        XCTAssertTrue(
            waitForSidebarClosed(),
            "Right sidebar should close after Alt+Cmd+B when it was open"
        )
    }

    func testToggleRightSidebarIsIdempotentAcrossMultipleCycles() {
        ensureSidebarClosed()

        for cycle in 1...3 {
            toggleRightSidebar()
            XCTAssertTrue(waitForSidebarOpen(timeout: 5), "Cycle \(cycle): sidebar should open")
            toggleRightSidebar()
            XCTAssertTrue(waitForSidebarClosed(timeout: 5), "Cycle \(cycle): sidebar should close")
        }
    }

    // MARK: - Toggle Right Sidebar via View menu

    func testViewMenuContainsToggleRightSidebarItem() {
        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 5), "View menu should exist")
        viewMenu.click()
        let menuItem = app.menuItems["Right Sidebar"]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 3),
            "View menu should contain 'Right Sidebar' item"
        )
        // Dismiss menu without activating.
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Agent sessions panel toggle (⇧⌘B) still works

    func testAgentSessionsToggleStillOpensSidebarWhenClosed() {
        // ⇧⌘B should open the sidebar (and ensure agent sessions widget is expanded)
        // even when the whole sidebar is closed.
        ensureSidebarClosed()
        toggleAgentSessions()
        XCTAssertTrue(
            waitForSidebarOpen(),
            "⇧⌘B should open the right sidebar when it is closed"
        )
    }
}
