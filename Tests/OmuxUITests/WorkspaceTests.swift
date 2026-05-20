import XCTest

// MARK: - Helpers

extension WorkspaceTests {
    /// Returns all workspace sidebar item buttons using the "omux.workspaceItem." identifier prefix.
    func workspaceItemButtons() -> XCUIElementQuery {
        let prefix = A11yID.workspaceItemPrefix
        return app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        )
    }

    /// Waits for at least `count` workspace item buttons to exist.
    @discardableResult
    func waitForWorkspaceItems(atLeast count: Int, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "count >= \(count)")
        let result = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: predicate, object: workspaceItemButtons())
        ], timeout: timeout)
        return result == .completed
    }
}

final class WorkspaceTests: OmuxUITestsBase {
    func testWorkspaceCreation() {
        // Trigger new workspace via the Workspace menu.
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["Workspace"].click()
        menuBar.menuBarItems["Workspace"].menuItems["New Workspace"].click()

        let workspaceList = app.groups[A11yID.workspaceList.rawValue]
        let predicate = NSPredicate(format: "count > 0")
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: workspaceList.children(matching: XCUIElement.ElementType.any)
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Workspace list should contain at least one entry within 5 seconds")
    }

    func testRenameWorkspace() {
        let menuBar = app.menuBars.firstMatch

        // Open the rename prompt via Workspace → Rename Workspace…
        menuBar.menuBarItems["Workspace"].click()
        menuBar.menuBarItems["Workspace"].menuItems["Rename Workspace…"].click()

        // The rename sheet should appear on the main window.
        let sheet = app.windows[A11yID.mainWindow.rawValue].sheets.firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "Rename Workspace sheet should appear within 5 seconds"
        )

        // Clear the existing name and type a new one.
        let nameField = sheet.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Name text field should exist in the sheet")
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("My Renamed Workspace")

        // Click Rename to confirm.
        sheet.buttons["Rename"].click()

        // Sheet should dismiss.
        let dismissedPredicate = NSPredicate(format: "exists == false")
        let dismissedExpectation = XCTNSPredicateExpectation(predicate: dismissedPredicate, object: sheet)
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissedExpectation], timeout: 3),
            .completed,
            "Rename sheet should dismiss within 3 seconds"
        )
    }

    func testDeleteWorkspace() {
        let menuBar = app.menuBars.firstMatch

        // Record how many workspace items exist before creating the extra one.
        _ = waitForWorkspaceItems(atLeast: 1)
        let preCreateCount = workspaceItemButtons().count

        // Create a second workspace so we have one to delete.
        menuBar.menuBarItems["Workspace"].click()
        menuBar.menuBarItems["Workspace"].menuItems["New Workspace"].click()

        // Wait until the new workspace item is reflected in the sidebar.
        _ = waitForWorkspaceItems(atLeast: preCreateCount + 1)
        let postCreateCount = workspaceItemButtons().count

        // Delete the active (second) workspace.
        menuBar.menuBarItems["Workspace"].click()
        menuBar.menuBarItems["Workspace"].menuItems["Delete Workspace"].click()

        // App should still be running with at least one workspace remaining.
        XCTAssertTrue(
            app.state == .runningForeground,
            "App should still be running after deleting a workspace"
        )
        let workspaceList = app.groups[A11yID.workspaceList.rawValue]
        XCTAssertTrue(
            workspaceList.waitForExistence(timeout: 3),
            "Workspace list should still be visible after deletion"
        )
        // The item count should have decreased back toward the pre-create level.
        let postDeleteResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < \(postCreateCount)"),
            object: workspaceItemButtons()
        )], timeout: 5)
        XCTAssertEqual(postDeleteResult, .completed, "Workspace item count should decrease after deletion")
    }

    // MARK: - Drag/drop: workspace reorder

    func testDragWorkspaceToReorder() {
        let menuBar = app.menuBars.firstMatch

        // Create a second workspace so there are two to reorder.
        menuBar.menuBarItems["Workspace"].click()
        menuBar.menuBarItems["Workspace"].menuItems["New Workspace"].click()

        XCTAssertTrue(
            waitForWorkspaceItems(atLeast: 2),
            "Two workspace item buttons should be visible after creating a second workspace"
        )

        let items = workspaceItemButtons()
        let sourceItem = items.element(boundBy: 0)
        let targetItem = items.element(boundBy: 1)

        XCTAssertTrue(sourceItem.waitForExistence(timeout: 5), "Source workspace item should exist")
        XCTAssertTrue(targetItem.waitForExistence(timeout: 5), "Target workspace item should exist")

        // Drag the first workspace onto the second to reorder.
        // Use coordinate-based drag to bypass the hittability gate on headless runners.
        sourceItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo: targetItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))

        // App should still be alive with at least one workspace showing.
        XCTAssertTrue(
            waitForWorkspaceItems(atLeast: 1),
            "At least one workspace item should remain after drag"
        )
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after workspace drag")
    }
}
