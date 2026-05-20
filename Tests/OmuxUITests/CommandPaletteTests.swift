import XCTest

final class CommandPaletteTests: OmuxUITestsBase {
    func testCommandPaletteOpenClose() {
        // Open the command palette via the View menu.
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Command Palette"].click()

        let palette = app.groups[A11yID.commandPalette.rawValue]
        XCTAssertTrue(
            palette.waitForExistence(timeout: 3),
            "Command palette element should exist within 3 seconds of opening"
        )

        // Dismiss with Escape.
        app.typeKey(.escape, modifierFlags: [])

        let dismissedPredicate = NSPredicate(format: "exists == false")
        let dismissedExpectation = XCTNSPredicateExpectation(predicate: dismissedPredicate, object: palette)
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissedExpectation], timeout: 2),
            .completed,
            "Command palette should disappear within 2 seconds of pressing Escape"
        )
    }

    // MARK: - Theme switching

    func testThemeSwitchViaCommandPalette() {
        // Open the command palette.
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["View"].click()
        menuBar.menuBarItems["View"].menuItems["Command Palette"].click()

        let palette = app.groups[A11yID.commandPalette.rawValue]
        XCTAssertTrue(palette.waitForExistence(timeout: 3), "Command palette should appear")

        // Wait deterministically for the search field to exist before interacting.
        let searchField = palette.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Palette search field should be accessible")

        // Use coordinate-based click to bypass XCUITest's hittability gate.
        // On headless CI runners, element-level click() on NSTextField fails with
        // "not hittable" when the window is not the key window. Coordinate synthesis
        // injects the event at the screen position directly, bypassing that check.
        searchField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        // Verify row 0 appears in the accessibility tree (unfiltered state).
        nonisolated(unsafe) let rowPredicate = NSPredicate(format: "identifier == %@", "\(A11yID.commandPaletteRowPrefix)0")
        let initialRow = app.descendants(matching: .any).matching(rowPredicate).firstMatch
        XCTAssertTrue(
            initialRow.waitForExistence(timeout: 5),
            "Row 0 should be visible in accessibility tree when palette opens with all commands"
        )

        // Type ">Switch Theme" — the ">" prefix activates command mode.
        searchField.typeText(">Switch Theme")

        // Re-query row 0 after typing — the previous row elements were destroyed and recreated.
        let switchThemeRow = app.descendants(matching: .any).matching(rowPredicate).firstMatch
        XCTAssertTrue(
            switchThemeRow.waitForExistence(timeout: 5),
            "First command palette result row should appear after typing 'Switch Theme'"
        )

        // Click it to enter the theme sub-palette.
        switchThemeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        // Now type a known built-in theme name to narrow the results.
        app.typeKey("a", modifierFlags: .command) // clear any existing query
        app.typeText("dracula")

        // Wait for a result row to appear in the sub-palette.
        let themeRow = app.descendants(matching: .any).matching(rowPredicate).firstMatch
        XCTAssertTrue(
            themeRow.waitForExistence(timeout: 5),
            "Theme result row for 'dracula' should appear in sub-palette"
        )

        // Click it to commit the theme switch.
        themeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        // The palette should close (theme is applied and palette dismissed).
        let dismissed = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter.wait(for: [
                XCTNSPredicateExpectation(predicate: dismissed, object: palette)
            ], timeout: 3),
            .completed,
            "Command palette should dismiss after theme selection"
        )
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after theme switch")
    }
}

