## 1. Accessibility Identifiers

- [x] 1.1 Add a public `A11yID` enum to `Sources/OmuxAppShell/` with string cases for `mainWindow`, `workspaceList`, `paneContainer`, `commandPalette`, and `settingsWindow`
- [x] 1.2 Set `.accessibilityIdentifier(A11yID.mainWindow)` on the main `NSWindow` or its root view in `OmuxAppShell`
- [x] 1.3 Set `.accessibilityIdentifier(A11yID.workspaceList)` on the workspace list view
- [x] 1.4 Set `.accessibilityIdentifier(A11yID.paneContainer)` on the pane container view
- [x] 1.5 Set `.accessibilityIdentifier(A11yID.commandPalette)` on the command palette view
- [ ] 1.6 Set `.accessibilityIdentifier(A11yID.settingsWindow)` on the settings window or its root view — **follow-up**: no dedicated settings window exists yet; `SettingsTests` exercises the sidebar toggle instead
- [ ] 1.7 Verify identifiers resolve correctly in Accessibility Inspector on a local build — **follow-up**: manual verification required

## 2. OMUX_UI_TEST Environment Flag

- [x] 2.1 Read `OMUX_UI_TEST` from `ProcessInfo.processInfo.environment` at app startup in `Sources/OpenMUXApp/main.swift`
- [x] 2.2 When `OMUX_UI_TEST=1`, bypass or stub Metal/GPU-dependent initialisation in the terminal bridge (e.g. skip `libghostty` surface creation)
- [ ] 2.3 Confirm the app reaches its main window without crashing when launched with the flag set and no GPU available — **follow-up**: requires headless CI environment to confirm

## 3. OmuxUITests SPM Target

- [x] 3.1 Create `Tests/OmuxUITests/` directory with a placeholder `OmuxUITestsBase.swift` that imports `XCTest` and `OmuxAppShell`
- [x] 3.2 Add `.testTarget(name: "OmuxUITests", dependencies: ["OmuxAppShell"], path: "Tests/OmuxUITests")` to `Package.swift`
- [x] 3.3 Confirm `swift build --target OmuxUITests` (or equivalent) compiles without errors

## 4. Xcode Scheme Setup

- [x] 4.1 Add a `make generate-xcodeproj` Makefile target that runs `xcodegen generate --spec project.yml` and produces `OpenMUX.xcodeproj`
- [x] 4.2 Verify that `xcodebuild -list -project OpenMUX.xcodeproj` shows `OmuxUITests` as a test target under the `OmuxUITests` scheme
- [x] 4.3 Add `OpenMUX.xcodeproj` to `.gitignore` (generated on demand, not committed)

## 5. Test Cases

- [x] 5.1 Write `AppLaunchTests.swift`: test that app launches, main window is hittable within 10 s, and terminates cleanly
- [x] 5.2 Write `WorkspaceTests.swift`: test that triggering new-workspace produces an entry in `A11yID.workspaceList` within 5 s
- [x] 5.3 Write `PaneTests.swift`: test that split-pane produces two pane elements in `A11yID.paneContainer`, then close-pane reduces count to one
- [x] 5.4 Write `CommandPaletteTests.swift`: test that the palette opens (element exists within 3 s) and closes on Escape (element gone within 2 s)
- [x] 5.5 Write `SettingsTests.swift`: test that the workspace sidebar toggles off (element hidden within 3 s) and back on (element visible within 3 s) via View → Toggle Workspace Column
- [x] 5.6 Ensure all tests use `waitForExistence(timeout:)` or `XCTNSPredicateExpectation`; remove any `Thread.sleep` calls
- [x] 5.7 Set `app.launchEnvironment["OMUX_UI_TEST"] = "1"` in a shared `setUp()` base class used by all test files

## 6. Makefile Target

- [x] 6.1 Add `ui-test` to the `.PHONY` list in `Makefile`
- [x] 6.2 Implement `ui-test` target: call `make generate-xcodeproj` then `xcodebuild test -project OpenMUX.xcodeproj -scheme OmuxUITests -destination "platform=macOS" -resultBundlePath .build/ui-test-results.xcresult`
- [x] 6.3 Add `ui-test` description to `make help` output

## 7. GitHub Actions CI Job

- [x] 7.1 Add a `ui-test` job to `.github/workflows/ci.yml` with `runs-on: macos-15`, `needs: verify`, and `timeout-minutes: 20`
- [x] 7.2 Reuse the Ghostty build cache in the `ui-test` job using the same cache key as the `verify` job
- [x] 7.3 Add a path filter (`paths`) to the `ui-test` job so it only runs when `Sources/OpenMUXApp/**`, `Sources/OmuxAppShell/**`, or `Tests/OmuxUITests/**` change
- [x] 7.4 Add an `upload-artifact` step that uploads `.build/ui-test-results.xcresult` on failure using `if: failure()`
- [x] 7.5 Run `make setup` in the `ui-test` job before `make ui-test` to ensure the Ghostty runtime is available

## 8. Validation

- [x] 8.1 Run `make ui-test` locally; confirm all test cases pass (the implementation includes 14 individual test methods across five test suite files: AppLaunchTests, WorkspaceTests, PaneTests, CommandPaletteTests, SettingsTests)
- [x] 8.2 Open a draft pull request and confirm the `ui-test` GitHub Actions job runs and passes
- [x] 8.3 Introduce a deliberate test failure, confirm the job fails and the `.xcresult` artifact is uploaded
- [x] 8.4 Revert the deliberate failure and confirm the job returns to green
- [x] 8.5 Run `make smoke` and `make verify` to confirm existing test layers are unaffected
