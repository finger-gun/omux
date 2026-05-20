import XCTest

// OmuxUITestsBase is the shared base class for all UI test cases.
// It launches the debug .app bundle (dev.fingergun.omux.debug) produced by
// Scripts/wrap-app-for-uitest.sh so it never interferes with an installed
// OpenMUX instance (dev.fingergun.omux).
// The OMUX_UI_TEST flag bypasses GPU/Metal initialisation on headless runners.
//
// The app is launched once per test class (via the class-level setUp/tearDown
// overrides) rather than once per test method. This avoids the overhead of
// 14+ app restarts while still providing a clean state between test classes.
//
// Note: XCTest always calls setUp/tearDown on the main thread, so
// nonisolated(unsafe) is safe here — no concurrent access occurs.

@MainActor
class OmuxUITestsBase: XCTestCase {
    // Shared across all tests in the same class.
    nonisolated(unsafe) static var sharedApp: XCUIApplication!

    // Per-test convenience accessor.
    var app: XCUIApplication { OmuxUITestsBase.sharedApp }

    // Called once before the first test method in the class runs.
    override class func setUp() {
        super.setUp()

        let a = XCUIApplication(bundleIdentifier: "dev.fingergun.omux.debug")
        a.launchEnvironment["OMUX_UI_TEST"] = "1"
        // Prevent the app from loading persisted workspace state during tests.
        a.launchEnvironment["OMUX_RESET_WORKSPACE"] = "1"
        sharedApp = a
        a.launch()

        // Wait for the main window to confirm the app is ready.
        let mainWindow = a.windows.matching(identifier: A11yID.mainWindow.rawValue).firstMatch
        let appeared = mainWindow.waitForExistence(timeout: 15)
        assert(appeared, "Main window must appear before any test interactions")
    }

    // Called once after the last test method in the class finishes.
    override class func tearDown() {
        if sharedApp?.state != .notRunning {
            sharedApp.terminate()
        }
        sharedApp = nil
        super.tearDown()
    }

    // Per-test setUp: stop the test run on the first failure so that a broken
    // state doesn't cascade through remaining tests in the session.
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
}
