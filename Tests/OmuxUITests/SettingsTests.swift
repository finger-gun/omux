import XCTest

final class SettingsTests: OmuxUITestsBase {
    func testToggleSidebar() {
        let menuBar = app.menuBars.firstMatch

        // The workspace list (sidebar) should be visible on launch.
        let workspaceList = app.groups[A11yID.workspaceList.rawValue]
        XCTAssertTrue(
            workspaceList.waitForExistence(timeout: 5),
            "Workspace list should be visible on launch"
        )

        // Toggle sidebar off via View menu.
        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Toggle Workspace Column"].click()

        let hiddenPredicate = NSPredicate(format: "exists == false")
        let hiddenExpectation = XCTNSPredicateExpectation(predicate: hiddenPredicate, object: workspaceList)
        XCTAssertEqual(
            XCTWaiter.wait(for: [hiddenExpectation], timeout: 3),
            .completed,
            "Workspace list should hide within 3 seconds of toggling"
        )

        // Toggle sidebar back on.
        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Toggle Workspace Column"].click()

        XCTAssertTrue(
            workspaceList.waitForExistence(timeout: 3),
            "Workspace list should reappear after toggling back"
        )
    }
}
