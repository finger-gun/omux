import XCTest

final class AppLaunchTests: OmuxUITestsBase {
    func testAppLaunches() {
        let mainWindow = app.windows.matching(identifier: A11yID.mainWindow.rawValue).firstMatch
        let exists = mainWindow.waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "Main window should appear within 10 seconds of launch")
        XCTAssertTrue(mainWindow.isHittable, "Main window should be hittable")
    }
}
