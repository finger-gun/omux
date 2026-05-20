import XCTest

// OmuxUITestsBase is the shared base class for all UI test cases.
// It launches the debug .app bundle (dev.fingergun.omux.debug) produced by
// Scripts/wrap-app-for-uitest.sh so it never interferes with an installed
// OpenMUX instance (dev.fingergun.omux).
// The OMUX_UI_TEST flag bypasses GPU/Metal initialisation on headless runners.
//
// Note: XCTest always calls setUp/tearDown on the main thread, so
// nonisolated(unsafe) is safe here — no concurrent access occurs.

class OmuxUITestsBase: XCTestCase {
    nonisolated(unsafe) var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        // nonisolated context but XCTest guarantees main-thread execution.
        let a = XCUIApplication(bundleIdentifier: "dev.fingergun.omux.debug")
        a.launchEnvironment["OMUX_UI_TEST"] = "1"
        // Prevent the app from loading persisted workspace state during tests.
        a.launchEnvironment["OMUX_RESET_WORKSPACE"] = "1"
        app = a
        app.launch()
        // Wait for the main window before any test interaction.
        // This also confirms the app is ready and frontmost.
        let mainWindow = app.windows.matching(identifier: A11yID.mainWindow.rawValue).firstMatch
        let appeared = mainWindow.waitForExistence(timeout: 15)
        XCTAssertTrue(appeared, "Main window must appear before test interactions")
    }

    override func tearDown() {
        // Terminate only if the app is still running to avoid double-terminate crashes.
        if app?.state == .runningForeground || app?.state == .runningBackground {
            app.terminate()
        }
        app = nil
        super.tearDown()
    }
}
