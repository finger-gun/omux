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
// MainActor.assumeIsolated is safe here — no concurrent access occurs.

@MainActor
class OmuxUITestsBase: XCTestCase {
    // Shared across all tests in the same class.
    nonisolated(unsafe) static var sharedApp: XCUIApplication!

    // Per-test convenience accessor.
    var app: XCUIApplication { OmuxUITestsBase.sharedApp }

    // Called once before the first test method in the class runs.
    // XCTest guarantees class setUp/tearDown run on the main thread, so
    // MainActor.assumeIsolated is safe here.
    nonisolated override class func setUp() {
        super.setUp()

        MainActor.assumeIsolated {
            let a = XCUIApplication(bundleIdentifier: "dev.fingergun.omux.debug")
            a.launchEnvironment["OMUX_UI_TEST"] = "1"
            // Prevent the app from loading persisted workspace state during tests.
            a.launchEnvironment["OMUX_RESET_WORKSPACE"] = "1"
            sharedApp = a
            a.launch()

            // Wait for the main window to confirm the app is ready.
            let mainWindow = a.windows.matching(identifier: A11yID.mainWindow.rawValue).firstMatch
            let appeared = mainWindow.waitForExistence(timeout: 15)
            XCTAssertTrue(appeared, "Main window must appear before any test interactions")

            // Ensure the app is front-most and the window is key before any test
            // interacts with on-screen elements. On headless CI runners the app may
            // exist in the a11y tree but coordinate-based gestures (rightClick,
            // doubleClick, press:thenDragTo:) fail unless the window is the key
            // window. We use two steps:
            // 1. activate() makes the app frontmost.
            // 2. Click the window's content area (below the titlebar) to force the
            //    window server to grant key-window status — this works even on
            //    headless runners where makeKeyAndOrderFront can be ignored.
            a.activate()
            // Click centre of the window content area. The window titlebar is ~28pt
            // tall; clicking at (0.5, 0.6) lands safely in the terminal content and
            // makes the window key without triggering any UI action.
            mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).click()

            // Wait for the main window to become hittable (confirms window is key).
            let hittable = NSPredicate(format: "isHittable == true")
            _ = XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: hittable, object: mainWindow)],
                timeout: 5
            )
        }
    }

    // Called once after the last test method in the class finishes.
    nonisolated override class func tearDown() {
        MainActor.assumeIsolated {
            if let app = sharedApp, app.state != .notRunning {
                app.terminate()
            }
            sharedApp = nil
        }
        super.tearDown()
    }

    // Per-test setUp: stop the test run on the first failure so that a broken
    // state doesn't cascade through remaining tests in the session.
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
}
