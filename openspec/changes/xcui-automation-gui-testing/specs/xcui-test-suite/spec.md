## ADDED Requirements

### Requirement: XCUITest target exists
The repository SHALL contain an `OmuxUITests` test target that uses `XCTest` and `XCUIApplication` to drive the OpenMUXApp process through the macOS accessibility layer.

#### Scenario: Target is declared in Package.swift
- **WHEN** a developer inspects `Package.swift`
- **THEN** a `.testTarget(name: "OmuxUITests", ...)` entry is present with its sources under `Tests/OmuxUITests/`

#### Scenario: Target builds without errors
- **WHEN** `xcodebuild build-for-testing -scheme OmuxUITests` is executed
- **THEN** the build succeeds and the `OmuxUITests` bundle is produced with no compile errors

### Requirement: Accessibility identifiers are stable and centralised
The `OmuxAppShell` module SHALL expose a public `A11yID` enum whose string cases are set as `.accessibilityIdentifier` on all key UI elements used by the test suite.

#### Scenario: Enum is importable from the test target
- **WHEN** `OmuxUITests` imports `OmuxAppShell`
- **THEN** `A11yID` is accessible and its cases compile without ambiguity

#### Scenario: Identifier is present on main window
- **WHEN** the app launches and the accessibility tree is queried
- **THEN** `XCUIApplication().windows[A11yID.mainWindow]` resolves to an existing, hittable element

#### Scenario: Identifier is present on command palette
- **WHEN** the command palette is open
- **THEN** `XCUIApplication().otherElements[A11yID.commandPalette]` resolves to an existing element

### Requirement: App launch test passes
The test suite SHALL contain a test that asserts the app reaches a usable foreground state within a defined timeout.

#### Scenario: App launches and main window appears
- **WHEN** `XCUIApplication().launch()` is called
- **THEN** the main window exists and `isHittable` returns `true` within 10 seconds

#### Scenario: App terminates cleanly
- **WHEN** `XCUIApplication().terminate()` is called after a successful launch
- **THEN** the process exits with code 0 and no crash report is written

### Requirement: Workspace creation test passes
The test suite SHALL contain a test that creates a new workspace and asserts it appears in the workspace list.

#### Scenario: New workspace appears after creation action
- **WHEN** the new-workspace action is triggered via the UI
- **THEN** a new workspace entry is visible in the workspace list element identified by `A11yID.workspaceList` within 5 seconds

### Requirement: Pane split test passes
The test suite SHALL contain a test that splits the active pane and asserts a second pane is present.

#### Scenario: Split produces two panes
- **WHEN** the split-pane action is triggered
- **THEN** the pane container identified by `A11yID.paneContainer` contains exactly two pane elements

### Requirement: Pane close test passes
The test suite SHALL contain a test that closes one pane and asserts only one pane remains.

#### Scenario: Close reduces pane count by one
- **WHEN** a split has produced two panes and the close-pane action is triggered on the active pane
- **THEN** the pane container contains exactly one pane element within 5 seconds

### Requirement: Command palette open/close test passes
The test suite SHALL contain a test that opens and dismisses the command palette.

#### Scenario: Command palette opens
- **WHEN** the keyboard shortcut or menu action for the command palette is triggered
- **THEN** the element identified by `A11yID.commandPalette` exists and is hittable within 3 seconds

#### Scenario: Command palette closes on Escape
- **WHEN** the Escape key is sent while the command palette is open
- **THEN** the element identified by `A11yID.commandPalette` no longer exists within 2 seconds

### Requirement: Sidebar toggle test passes
The test suite SHALL contain a test that toggles the workspace sidebar (via View → Toggle Workspace Column) and asserts visibility changes.

#### Scenario: Sidebar hides after toggle
- **WHEN** the toggle-sidebar action is triggered (View → Toggle Workspace Column)
- **THEN** the element identified by `A11yID.workspaceList` no longer exists within 3 seconds

#### Scenario: Sidebar reappears after second toggle
- **WHEN** the toggle-sidebar action is triggered again
- **THEN** the element identified by `A11yID.workspaceList` exists and is visible within 3 seconds

### Requirement: Tests use explicit waits, not fixed sleeps
Every XCUITest assertion that depends on asynchronous UI state SHALL use `XCTNSPredicateExpectation` or `waitForExistence(timeout:)` rather than `Thread.sleep` or `sleep()`.

#### Scenario: Flakiness from race conditions is avoided
- **WHEN** a UI element takes variable time to appear (e.g. after an animation)
- **THEN** the test waits up to the defined timeout and fails with a descriptive message if the element does not appear, rather than failing intermittently due to timing

### Requirement: GPU/Metal initialisation is skippable under test
The app SHALL honour the environment variable `OMUX_UI_TEST=1` to disable or stub Metal/GPU-dependent initialisation paths, allowing the test suite to run on headless CI runners.

#### Scenario: App boots without Metal on CI
- **WHEN** `XCUIApplication` launches the app with `launchEnvironment["OMUX_UI_TEST"] = "1"`
- **THEN** the app reaches its main window without crashing due to a missing GPU or Metal device
