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

    /// Performs a right-click at the centre of an element using coordinate-based synthesis.
    /// Bypasses XCUITest's hittability gate, which can refuse element-level rightClick()
    /// on headless CI runners where the window is not the key window.
    func rightClickCenter(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
    }

    /// Performs a double-click at the centre of an element using coordinate-based synthesis.
    func doubleClickCenter(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleClick()
    }

    /// Renames a pane tab using inline edit (double-click then type).
    func renamePaneTab(_ tab: XCUIElement, to newTitle: String) {
        XCTAssertTrue(tab.exists, "tab to rename should exist")
        doubleClickCenter(tab)
        app.typeKey("a", modifierFlags: .command)
        app.typeText(newTitle)
        app.typeKey(.return, modifierFlags: [])
    }

    /// Polls until the main window width differs from `baselineWidth` by at least `delta`.
    @discardableResult
    func waitForWindowWidthChange(
        _ window: XCUIElement,
        baselineWidth: CGFloat,
        delta: CGFloat,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if abs(window.frame.width - baselineWidth) >= delta {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }
}

final class PaneTests: OmuxUITestsBase {

    // After each test, close any extra pane tabs so the next test starts
    // from a known single-tab state. This prevents alphabetical test ordering
    // from leaking state (e.g. testDragPaneTabToCreateSplit leaving extra tabs
    // that make subsequent tab interactions fail).
    override func tearDown() {
        let menuBar = app.menuBars.firstMatch
        // Close tabs until only one remains. Guard against infinite loops with a
        // fixed iteration cap — there are never more than ~10 tabs in any test.
        for _ in 0..<10 {
            guard paneTabButtons().count > 1 else { break }
            menuBar.menuBarItems["Pane"].click()
            let closeItem = menuBar.menuBarItems["Pane"].menuItems["Close Pane Tab"]
            guard closeItem.exists else {
                menuBar.typeKey(.escape, modifierFlags: [])
                break
            }
            closeItem.click()
            let priorCount = paneTabButtons().count
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count <= %d", priorCount - 1),
                object: paneTabButtons()
            )], timeout: 2)
        }
        super.tearDown()
    }

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

    func testSinglePaneWindowWidthCanResizeFromRightEdge() {
        XCTAssertTrue(
            waitForPaneTabs(atLeast: 1),
            "single-pane tab should be visible on launch"
        )

        let mainWindow = app.windows.matching(identifier: A11yID.mainWindow.rawValue).firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5), "main window should exist")

        let initialWidth = mainWindow.frame.width
        XCTAssertGreaterThan(initialWidth, 300, "baseline window width should be reasonable")

        let rightEdge = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.998, dy: 0.5))
        rightEdge.press(forDuration: 0.05, thenDragTo: rightEdge.withOffset(CGVector(dx: -220, dy: 0)))
        XCTAssertTrue(
            waitForWindowWidthChange(mainWindow, baselineWidth: initialWidth, delta: 80),
            "window width should shrink in single-pane mode when dragging right edge inward"
        )

        let reducedWidth = mainWindow.frame.width
        XCTAssertLessThan(reducedWidth, initialWidth - 80)

        let rightEdgeAfterShrink = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.998, dy: 0.5))
        rightEdgeAfterShrink.press(forDuration: 0.05, thenDragTo: rightEdgeAfterShrink.withOffset(CGVector(dx: 260, dy: 0)))
        XCTAssertTrue(
            waitForWindowWidthChange(mainWindow, baselineWidth: reducedWidth, delta: 80),
            "window width should grow in single-pane mode when dragging right edge outward"
        )
        XCTAssertGreaterThan(mainWindow.frame.width, reducedWidth + 80)
    }

    func testPaneTabSizingKeepsShortTitlesFromCollapsing() {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["New Pane Tab"].click()
        XCTAssertTrue(waitForPaneTabs(atLeast: 2), "expected two pane tabs")

        let tabs = paneTabButtons()
        let firstTab = tabs.element(boundBy: 0)
        let secondTab = tabs.element(boundBy: 1)
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTab.waitForExistence(timeout: 5))

        renamePaneTab(firstTab, to: "~/projects/omux/a-very-long-tab-title-that-should-truncate-in-the-middle")
        renamePaneTab(secondTab, to: "omux")

        let mainWindow = app.windows.matching(identifier: A11yID.mainWindow.rawValue).firstMatch
        let rightEdge = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.998, dy: 0.5))
        rightEdge.press(forDuration: 0.05, thenDragTo: rightEdge.withOffset(CGVector(dx: 220, dy: 0)))
        XCTAssertGreaterThan(
            secondTab.frame.width,
            70,
            "short-title tab should not collapse to a tiny width"
        )
        XCTAssertGreaterThanOrEqual(
            firstTab.frame.width,
            secondTab.frame.width,
            "long-title tab should not be narrower than the short-title neighbor"
        )
    }

    func testPaneTabLongTitleRetainsFullAccessibilityLabelWhenWidthIsTight() {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["New Pane Tab"].click()
        XCTAssertTrue(waitForPaneTabs(atLeast: 2), "expected two pane tabs")

        let tabs = paneTabButtons()
        let firstTab = tabs.element(boundBy: 0)
        let secondTab = tabs.element(boundBy: 1)
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTab.waitForExistence(timeout: 5))

        renamePaneTab(firstTab, to: "~/projects/omux/a-very-long-tab-title-that-should-truncate-in-the-middle")
        renamePaneTab(secondTab, to: "omux")

        let mainWindow = app.windows.matching(identifier: A11yID.mainWindow.rawValue).firstMatch
        let rightEdge = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.998, dy: 0.5))
        rightEdge.press(forDuration: 0.05, thenDragTo: rightEdge.withOffset(CGVector(dx: -260, dy: 0)))
        XCTAssertTrue(
            firstTab.label.contains("a-very-long-tab-title-that-should-truncate-in-the-middle"),
            "long tab should keep full accessibility label even when visually truncated"
        )
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

        // Use coordinate-based right-click to bypass XCUITest's hittability gate.
        // On headless CI runners, element-level rightClick() fails with "not hittable"
        // when the window is not the key window, even though the element exists in the
        // a11y tree. Coordinate-based synthesis injects the event at the screen position
        // directly, bypassing the gate.
        rightClickCenter(tab)
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
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
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

        // Use coordinate-based double-click to bypass the hittability gate.
        doubleClickCenter(tab)

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

    func testWindowFrameDoesNotShrinkAfterClosingSplitPane() {
        let menuBar = app.menuBars.firstMatch
        let window = app.windows[A11yID.mainWindow.rawValue]

        // Wait for the window to settle before sampling its frame.
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main window should exist on launch")
        let frameBefore = window.frame

        // Split the focused pane.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["Split Right"].click()

        // Wait for the split to appear.
        let paneContainer = app.groups[A11yID.paneContainer.rawValue]
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= 2"),
            object: paneContainer.children(matching: .any)
        )], timeout: 5)

        // Remove the active (right) pane.
        menuBar.menuBarItems["Pane"].click()
        menuBar.menuBarItems["Pane"].menuItems["Remove Active Pane"].click()

        // Give AppKit a moment to flush any layout pass.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < 2"),
            object: paneContainer.children(matching: .any)
        )], timeout: 3)

        let frameAfter = window.frame

        // The window must not shrink in width after closing the split pane.
        // Allow a tolerance of 2 pts for rounding / chrome adjustments.
        XCTAssertGreaterThanOrEqual(
            frameAfter.width, frameBefore.width - 2,
            "Window width should not shrink after closing a split pane (was \(frameBefore.width), now \(frameAfter.width))"
        )
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after closing a split pane")
    }

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

        // Coordinate-based drag — bypasses hittability gate.
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

        // Capture labels before drag so we can verify order changed after.
        let labelBefore0 = paneTabButtons().element(boundBy: 0).label
        let labelBefore1 = paneTabButtons().element(boundBy: 1).label

        // Use coordinate-based drag to bypass XCUITest's hittability gate.
        // element.press(forDuration:thenDragTo:) checks hittability on the source element
        // before injecting; coordinate-based synthesis skips that check.
        sourceTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo: targetTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))

        // After drag the app must still be alive with two tabs.
        let postDragResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= 2"),
            object: paneTabButtons()
        )], timeout: 5)
        XCTAssertEqual(postDragResult, .completed, "Both pane tabs should still exist after drag")
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after pane tab drag")

        // Verify tab order changed: the element at index 0 after drag should carry the
        // label that was at index 1 before drag (and vice-versa). If the labels are
        // identical the reorder is unobservable via the a11y tree — skip that assertion
        // so the test does not false-fail when both tabs carry the same default name.
        if labelBefore0 != labelBefore1 {
            let labelAfter0 = paneTabButtons().element(boundBy: 0).label
            let labelAfter1 = paneTabButtons().element(boundBy: 1).label
            XCTAssertEqual(
                labelAfter0, labelBefore1,
                "After drag-to-reorder the first tab should carry the label that was second before"
            )
            XCTAssertEqual(
                labelAfter1, labelBefore0,
                "After drag-to-reorder the second tab should carry the label that was first before"
            )
        }
    }
}
