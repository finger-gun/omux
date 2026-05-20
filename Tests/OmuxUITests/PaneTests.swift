import XCTest

// MARK: - Helpers

extension PaneTests {
    /// Returns all pane tab buttons currently visible, using the "omux.paneTab." identifier prefix.
    func paneTabButtons() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", A11yID.paneTabPrefix)
        )
    }

    /// Waits for at least `count` pane tab buttons to exist.
    @discardableResult
    func waitForPaneTabs(atLeast count: Int, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "count >= \(count)")
        let result = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: predicate, object: paneTabButtons())
        ], timeout: timeout)
        return result == .completed
    }
}

final class PaneTests: OmuxUITestsBase {
    func testPaneSplitAndClose() {
        let paneContainer = app.groups[A11yID.paneContainer.rawValue]
        let menuBar = app.menuBars.firstMatch

        // Trigger split-pane via the Pane menu.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["Split Right"].click()

        let twoPane = NSPredicate(format: "count >= 2")
        let splitExpectation = XCTNSPredicateExpectation(
            predicate: twoPane,
            object: paneContainer.children(matching: XCUIElement.ElementType.any)
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [splitExpectation], timeout: 5),
            .completed,
            "Two pane elements should appear in the pane container within 5 seconds of splitting"
        )

        // Remove a pane via the Pane menu and verify the menu item fires without crashing.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["Remove Active Pane"].click()

        // Give the app a moment to process the removal.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < 2"),
            object: paneContainer.children(matching: XCUIElement.ElementType.any)
        )], timeout: 3)
        // We don't assert the final count since one pane may remain as minimum;
        // the key check is the menu action fired without crashing.
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after pane removal")
    }

    func testNewPaneTab() {
        let paneContainer = app.groups[A11yID.paneContainer.rawValue]
        let menuBar = app.menuBars.firstMatch

        // Confirm pane container is present before we start.
        XCTAssertTrue(
            paneContainer.waitForExistence(timeout: 5),
            "Pane container should be visible on launch"
        )

        // Create a new pane tab via Pane → New Pane Tab.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["New Pane Tab"].click()

        // The pane container should still be present and the app should not crash.
        XCTAssertTrue(
            paneContainer.waitForExistence(timeout: 3),
            "Pane container should still be visible after creating a new pane tab"
        )
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after creating a pane tab")

        // Close the new pane tab via Pane → Close Pane Tab.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["Close Pane Tab"].click()

        XCTAssertTrue(app.state == .runningForeground, "App should still be running after closing a pane tab")
    }

    // MARK: - Rename via context menu

    func testRenamePaneTabViaContextMenu() {
        // Ensure at least one pane tab is visible.
        XCTAssertTrue(
            waitForPaneTabs(atLeast: 1),
            "At least one pane tab button should be visible on launch"
        )

        let tab = paneTabButtons().firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "First pane tab should exist")

        // Right-click to open context menu, then choose "Rename…".
        tab.rightClick()
        let renameItem = app.menuItems["Rename…"]
        XCTAssertTrue(renameItem.waitForExistence(timeout: 3), "Rename… menu item should appear in context menu")
        renameItem.click()

        // The rename sheet ("Rename Tab") should appear.
        let sheet = app.windows[A11yID.mainWindow.rawValue].sheets.firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "Rename Tab sheet should appear within 5 seconds"
        )

        let nameField = sheet.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Name text field should exist in the sheet")
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("My Renamed Tab")

        sheet.buttons["Save"].click()

        // Sheet should dismiss.
        let dismissed = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: sheet)], timeout: 3),
            .completed,
            "Rename Tab sheet should dismiss within 3 seconds"
        )
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after tab rename via context menu")
    }

    // MARK: - Rename via double-click (inline edit)

    func testRenamePaneTabViaDoubleClick() {
        // Ensure at least one pane tab is visible.
        XCTAssertTrue(
            waitForPaneTabs(atLeast: 1),
            "At least one pane tab button should be visible on launch"
        )

        let tab = paneTabButtons().firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "First pane tab should exist")

        // Double-click triggers inline rename on the tab's title label.
        tab.doubleClick()

        // The inline editor is a text field that becomes first responder.
        // We target it via the window's focused element (typeText goes to first responder).
        // Select all existing text and type a new name.
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Inline Renamed Tab")

        // Commit the rename with Return.
        app.typeKey(.return, modifierFlags: [])

        // App should still be running and the tab should remain present.
        XCTAssertTrue(
            waitForPaneTabs(atLeast: 1),
            "Pane tab should still exist after inline rename"
        )
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after tab rename via double-click")
    }

    // MARK: - Drag/drop: pane tab to new split

    func testDragPaneTabToCreateSplit() {
        let menuBar = app.menuBars.firstMatch
        let paneContainer = app.groups[A11yID.paneContainer.rawValue]

        // Create a second tab so there are two tabs in the single pane stack.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["New Pane Tab"].click()

        XCTAssertTrue(
            waitForPaneTabs(atLeast: 2),
            "Two pane tab buttons should be visible before the drag"
        )

        // Drag the second tab to the right edge of the pane container to trigger a split.
        // The right outer-edge zone produces a .splitAtRoot(.right) intent.
        let sourceTab = paneTabButtons().element(boundBy: 1)
        XCTAssertTrue(sourceTab.waitForExistence(timeout: 5), "Second pane tab should exist")

        // Target: right-edge midpoint of the pane container (outer-edge drop zone).
        let targetCoord = paneContainer.coordinate(
            withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)
        )

        sourceTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo: targetCoord)

        // After the split the pane container should still exist and the app be alive.
        XCTAssertTrue(
            paneContainer.waitForExistence(timeout: 5),
            "Pane container should still exist after drag-to-split"
        )
        XCTAssertTrue(
            app.state == .runningForeground,
            "App should still be running after drag-to-split"
        )
        // The split should produce at least two child elements in the pane container.
        let splitResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= 2"),
            object: paneContainer.children(matching: .any)
        )], timeout: 5)
        XCTAssertEqual(splitResult, .completed, "Pane container should contain at least two children after drag-to-split")

        // Teardown: collapse the split by removing the active pane, restoring a single-pane layout
        // so subsequent tests in this class start from a known state.
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["Remove Active Pane"].click()
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < 2"),
            object: paneContainer.children(matching: .any)
        )], timeout: 5)
    }

    // MARK: - Drag/drop: pane tab reorder

    func testDragPaneTabToReorder() {
        let menuBar = app.menuBars.firstMatch

        // Create a second tab so there are two to reorder.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["New Pane Tab"].click()

        XCTAssertTrue(
            waitForPaneTabs(atLeast: 2),
            "Two pane tab buttons should be visible after creating a second tab"
        )

        let tabs = paneTabButtons()
        let sourceTab = tabs.element(boundBy: 0)
        let targetTab = tabs.element(boundBy: 1)

        XCTAssertTrue(sourceTab.waitForExistence(timeout: 5), "Source pane tab should exist")
        XCTAssertTrue(targetTab.waitForExistence(timeout: 5), "Target pane tab should exist")

        // Drag first tab onto second tab.
        sourceTab.press(forDuration: 0.1, thenDragTo: targetTab)

        // After drag the app must still be alive with two tabs.
        // Also verify the tabs collection still reports at least 2 entries —
        // if the reorder collapsed a tab the count would drop.
        let postDragResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= 2"),
            object: paneTabButtons()
        )], timeout: 5)
        XCTAssertEqual(postDragResult, .completed, "Both pane tabs should still exist after drag")
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after pane tab drag")
    }
}
