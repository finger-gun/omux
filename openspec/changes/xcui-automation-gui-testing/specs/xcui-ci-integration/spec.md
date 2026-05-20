## ADDED Requirements

### Requirement: Makefile ui-test target exists
The `Makefile` SHALL contain a `ui-test` target that builds the app for testing and executes the `OmuxUITests` suite via `xcodebuild`.

#### Scenario: Target is listed in make help
- **WHEN** `make help` is run
- **THEN** `ui-test` appears in the output with a short description

#### Scenario: Target executes the suite
- **WHEN** `make ui-test` is run on a developer machine with Xcode installed
- **THEN** `xcodebuild test` is invoked with `-only-testing OmuxUITests` and the suite runs to completion

### Requirement: xcodebuild scheme is available
A scheme named `OmuxUITests` SHALL be resolvable by `xcodebuild` without requiring a manually maintained committed `.xcodeproj`. The scheme SHALL be generated on demand via `xcodegen` using `project.yml` (invoked by the Makefile `generate-xcodeproj` target) before the test step.

#### Scenario: Scheme generation succeeds before test run
- **WHEN** `make ui-test` is run from a clean checkout
- **THEN** the `generate-xcodeproj` step completes before `xcodebuild test` is invoked and the scheme is discoverable

#### Scenario: Scheme resolves the OmuxUITests target
- **WHEN** `xcodebuild -list` is run after scheme generation
- **THEN** `OmuxUITests` appears in the list of test targets for the `OmuxUITests` scheme

### Requirement: GitHub Actions ui-test job runs on macos-15
The `.github/workflows/ui-tests.yml` SHALL contain a `ui-test` job that:
- runs on `macos-15`
- executes `make ui-test`
- reports pass/fail as a required check on pull requests
- does NOT use `needs: verify` because it runs as a standalone workflow

#### Scenario: Job is triggered on pull request
- **WHEN** a pull request is opened or updated
- **THEN** the `ui-test` job is triggered automatically via the existing `on: pull_request` trigger

#### Scenario: Job uses cached Ghostty build
- **WHEN** the `ui-test` job runs and the Ghostty cache key matches
- **THEN** the Ghostty build step is skipped and the total job time is reduced

#### Scenario: Job reports failure on test regression
- **WHEN** a test in `OmuxUITests` fails
- **THEN** the `ui-test` job exits with a non-zero status and GitHub marks the check as failed

### Requirement: UI tests run headlessly without a physical display
The `xcodebuild test` invocation SHALL use `-destination "platform=macOS"` so that tests execute against the host macOS environment on the GitHub runner without requiring a connected display or virtual framebuffer setup.

#### Scenario: Tests run without display configuration
- **WHEN** `make ui-test` is executed on a `macos-15` GitHub-hosted runner
- **THEN** `xcodebuild` launches the app and runs all tests without errors related to display or screen availability

### Requirement: UI test job scope is limited to relevant paths
The `ui-test` job SHOULD only run when paths relevant to the UI test suite or the app shell change, to avoid unnecessary CI time on unrelated commits.

#### Scenario: Job is skipped for docs-only changes
- **WHEN** a pull request modifies only files under `docs/` or `openspec/`
- **THEN** the `ui-test` job is skipped via a path filter and does not consume runner minutes

#### Scenario: Job runs when test sources change
- **WHEN** a pull request modifies files under `Tests/OmuxUITests/` or `Sources/OpenMUXApp/` or `Sources/OmuxAppShell/`
- **THEN** the `ui-test` job runs

### Requirement: Test results are uploaded as CI artifacts
The `ui-test` job SHALL upload the `xcodebuild` result bundle as a GitHub Actions artifact on failure so that test logs and screenshots are inspectable without re-running.

#### Scenario: Result bundle is available after failure
- **WHEN** one or more tests in `OmuxUITests` fail
- **THEN** a `.xcresult` bundle is uploaded as a workflow artifact and is downloadable from the GitHub Actions run summary
