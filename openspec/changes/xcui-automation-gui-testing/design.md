## Context

OpenMUX has two existing test layers:

1. **Swift unit/integration tests** (`swift test`) — exercising individual SPM targets (`OmuxCore`, `OmuxAppShell`, `OmuxControlPlane`, etc.) in isolation, without a running app.
2. **Smoke tests** (`make smoke`, `make smoke-packaged-release`) — shell scripts that launch the app process, sample it with `sample(1)`, and assert it is alive; they verify nothing about the UI.

Neither layer can catch visual regressions, accessibility failures, or broken end-to-end workflows (e.g. a pane split that crashes at runtime, a command palette shortcut that no longer fires, or a workspace that silently fails to persist). XCUITest (via `XCUIApplication`) drives the live app process through the macOS accessibility API, filling this gap.

The app is structured as a Swift Package with `OpenMUXApp` as an executable target and `OmuxAppShell` as its library. GitHub Actions already runs on `macos-15` hosted runners; the existing `verify` job builds and unit-tests there without a display.

## Goals / Non-Goals

**Goals:**
- Add an `OmuxUITests` SPM test target with a first set of XCUITest cases covering: app launch/quit, workspace creation, pane split and close, command-palette open/close, and settings open/close
- Expose stable `accessibilityIdentifier` values on the key AppKit/SwiftUI views so tests can locate elements without relying on fragile label strings
- Add a `make ui-test` Makefile target that builds the app and executes the suite via `xcodebuild test`
- Add a `ui-test` job to `ci.yml` that runs the suite on `macos-15` in GitHub Actions

**Non-Goals:**
- Exhaustive pixel-perfect visual regression (no screenshot diffing)
- Testing terminal emulation fidelity or `libghostty` internals — those belong in unit tests
- Running UI tests on iOS/iPadOS simulators or any non-macOS platform
- Full accessibility audit or VoiceOver compliance (out of scope for v1)

## Decisions

### 1. XCUITest via `xcodebuild` rather than SwiftPM `swift test`

SwiftPM (`swift test`) does not support `XCUITest` targets — `XCUIApplication` requires a host app bundle, which only `xcodebuild` can orchestrate. The `make ui-test` target will call:

```
xcodebuild test \
  -scheme OpenMUXApp \
  -destination "platform=macOS" \
  -only-testing OmuxUITests
```

`xcodebuild` requires an Xcode project or workspace. Since OpenMUX uses SPM, we generate an Xcode project with `swift package generate-xcodeproj` (or check in a thin `.xcodeproj` that references the package). An alternative is to define a separate `Package-UITests.swift` that wraps the UI test target; however, `xcodebuild` with `-clonedSourcePackagesDirPath` is more idiomatic for CI.

**Decision**: Use `xcodebuild -scheme` with a generated or checked-in Xcode project. Generate on the fly in CI to avoid maintaining a committed `.xcodeproj`.

### 2. Accessibility identifier strategy

XCUITest locates elements via the accessibility tree. Hardcoded label strings are fragile (localisation, refactors). Instead:

- Assign string constants from a shared `A11yID` enum in `OmuxAppShell` (e.g. `A11yID.commandPalette`, `A11yID.workspaceList`)
- Set `.accessibilityIdentifier` on AppKit views and SwiftUI views at the site of definition
- Tests reference the same enum values (or a mirrored copy in the test target if SPM dependency isolation requires it)

**Decision**: Define `A11yID` as a public enum in `OmuxAppShell`; import it in `OmuxUITests`.

### 3. CI headless display

GitHub-hosted `macos-15` runners have Xcode installed and can run `xcodebuild` UI tests against `platform=macOS` without an explicit display server — macOS runners provide a virtual framebuffer by default when a test host is launched by `xcodebuild`. No `Xvfb` or additional setup is needed.

The `ui-test` CI job will reuse the same Ghostty cache as the `verify` job (via `needs: verify`) so it doesn't rebuild from scratch, but it will call `make setup` defensively if the cache is not hit.

### 4. SPM target structure

`XCUITest` targets must declare the host app. In a pure SPM context this requires the `.testTarget` to list the app's bundle identifier as `hostingAppBundleIdentifier`. This is supported in `Package.swift` via:

```swift
.testTarget(
    name: "OmuxUITests",
    dependencies: [],
    path: "Tests/OmuxUITests"
)
```

The hosting app association is handled via the `xcodebuild` scheme rather than inside `Package.swift` (SPM's native support for UI test host bundles is limited prior to Swift 5.10). Tests use `XCUIApplication(bundleIdentifier: "com.omux.OpenMUXApp")` to attach to the running app.

### 5. Scope of initial test cases

Keep the initial suite narrow and fast (target: < 2 minutes wall-clock). Cover the happy path only:

| Test | What it asserts |
|------|----------------|
| `testAppLaunches` | App reaches foreground, main window visible |
| `testWorkspaceCreation` | New workspace action creates a workspace entry |
| `testPaneSplit` | Split action produces a second pane |
| `testPaneClose` | Closing a pane removes it |
| `testCommandPaletteOpenClose` | Command palette appears and dismisses |
| `testSettingsOpenClose` | Settings window opens and closes |

## Risks / Trade-offs

- **`xcodebuild` project generation is slow** → Mitigated by caching `.build/` and running UI tests only when relevant paths change (path filter on `ci.yml`).
- **Accessibility identifiers are a maintenance burden** → Mitigated by centralising them in `A11yID`; renames are compile-time errors if the test target imports the enum.
- **GitHub runner GPU/Metal constraints** → The terminal renderer (`libghostty`) may fail to initialise without a GPU. Mitigation: detect and skip GPU-dependent startup in the test entry point using an environment variable (`OMUX_UI_TEST=1`) that disables Metal rendering and uses a software fallback or stub surface.
- **Test flakiness from animation timing** → Use `XCTNSPredicateExpectation` with explicit waits rather than fixed `sleep` calls.
- **`swift package generate-xcodeproj` is deprecated in recent toolchains** → Fallback: check in a minimal `OpenMUX.xcworkspace` + `OpenMUX.xcodeproj` that `swift package resolve` populates; document that this file must be regenerated when `Package.swift` changes.

## Open Questions

- Does the `macos-15` GitHub runner GPU environment allow `libghostty`/Metal to initialise, or must we unconditionally stub the terminal surface in UI test runs? Needs a spike run to confirm.
- Should `make ui-test` be part of `make verify` (always run) or a separate opt-in target? Recommend separate for now due to `xcodebuild` overhead; revisit when suite is stable and fast.
- Does the bundle identifier `com.omux.OpenMUXApp` match what is set in `Sources/OpenMUXApp/main.swift` or the Info.plist? Must be confirmed before tests can attach.
