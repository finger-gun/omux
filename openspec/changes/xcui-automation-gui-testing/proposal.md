## Why

OpenMUX currently has unit and integration tests for individual modules (Swift Package targets) and a smoke test that launches the app and samples its process, but no GUI-level tests that exercise real user-facing workflows end-to-end. XCUITest (XCUIAutomation) fills this gap: it drives the actual running application through the macOS accessibility layer, catching regressions that module-level tests cannot see — broken pane layouts, missing keyboard shortcuts, commands that never surface in the UI, and workspace state that doesn't survive a restart.

## What Changes

- Add a new `OmuxUITests` Xcode/SwiftPM test target using `XCTest` + `XCUIApplication`
- Implement an initial suite covering core end-to-end workflows: app launch, workspace creation, pane split/close, basic command-palette interaction, and settings open/close
- Add a `make ui-test` target that builds the app and runs the UI test suite headlessly via `xcodebuild test`
- Add a `ui-test` job to `.github/workflows/ci.yml` that runs on `macos-15` with a virtual display (or using `xcodebuild` with `-destination "platform=macOS"`) so the suite executes inside GitHub Actions without a physical screen

## Capabilities

### New Capabilities
- `xcui-test-suite`: XCUIAutomation test target wired to the OpenMUXApp bundle, covering launch, workspace, pane, command-palette, and settings workflows
- `xcui-ci-integration`: GitHub Actions job definition and Makefile target that builds and runs the UI test suite headlessly in CI

### Modified Capabilities
<!-- No existing spec-level requirements change; this adds a new test layer on top of existing behaviour -->

## Impact

- **Sources/OpenMUXApp**: The app target must expose accessibility identifiers on key UI elements so XCUITest can locate them reliably
- **Package.swift**: New `OmuxUITests` test target referencing `OpenMUXApp` (or its testable host)
- **Makefile**: New `ui-test` target
- **.github/workflows/ci.yml**: New `ui-test` job; must account for GitHub-hosted `macos-15` runner constraints (no GPU, headless display via `xcodebuild`)
- **No impact** on `libghostty` bridge, IPC, CLI, or extension points
- **No breaking changes** to existing interfaces
