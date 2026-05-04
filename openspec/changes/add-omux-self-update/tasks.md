## 1. Version and Release Metadata

- [x] 1.1 Add an OpenMUX version provider that resolves the installed version from app bundle metadata, packaged CLI resources, or repository-local `VERSION` during development.
- [x] 1.2 Update release packaging so app and CLI artifacts include the version data needed by `omux version`.
- [x] 1.3 Add `omux version` CLI handling and tests for successful offline version output.
- [x] 1.4 Add a GitHub Release metadata client that fetches latest release JSON, parses semantic versions, and locates the matching app archive plus `checksums.txt`.
- [x] 1.5 Add tests for release metadata parsing, up-to-date detection, newer-version detection, and fetch failure reporting.

## 2. Verified Update Staging

- [x] 2.1 Implement app archive and checksum download into a per-user temporary staging directory using absolute paths.
- [x] 2.2 Implement SHA-256 checksum verification for the selected app archive.
- [x] 2.3 Implement app archive unarchiving into staging and validation of `OpenMUX.app` bundle identifier and version.
- [x] 2.4 Implement writable install target selection for current app path, `/Applications/OpenMUX.app`, and `~/Applications/OpenMUX.app`.
- [x] 2.5 Add tests for checksum match, missing checksum, checksum mismatch, invalid staged bundle, staging cleanup, and writable target fallback.

## 3. Prompted Update Installation

- [x] 3.1 Add `omux update` CLI flow for discovery, up-to-date reporting, verified staging, and pre-install failure handling.
- [x] 3.2 Detect running OpenMUX instances by bundle identifier before replacement.
- [x] 3.3 Prompt interactively before closing a running OpenMUX app, with Return defaulting to yes and `n`/`N` cancelling.
- [x] 3.4 Copy the current `omux` executable into staging and spawn it as a detached helper with a manifest and log path.
- [x] 3.5 Implement the helper command to gracefully terminate OpenMUX, wait for exit with timeout, replace the app with rollback, reopen on success, log failures, and clean staging files.
- [x] 3.6 Add tests for prompt acceptance, prompt cancellation, no-running-app install path, helper manifest creation, timeout behavior, rollback behavior, and no hidden privilege escalation.

## 4. App-Side Update Availability

- [x] 4.1 Add an app-side update checker that runs asynchronously after launch and respects a cached conservative check interval.
- [x] 4.2 Store update availability state without blocking workspace restoration, terminal startup, rendering, or input.
- [x] 4.3 Render a workspace sidebar footer notice showing the available version and `omux update` command.
- [x] 4.4 Add tests for newer-version notice state, current-version/no-notice state, failed-check non-blocking behavior, cached interval behavior, and sidebar rendering.

## 5. Release Workflow and Documentation

- [x] 5.1 Ensure the release workflow continues to publish `OpenMUX-<version>-macos-unsigned.zip` and `checksums.txt` with a SHA-256 entry for the app archive.
- [x] 5.2 Document `omux version`, `omux update`, install target behavior, prompted app closure, temp staging, and unsigned archive limitations.
- [x] 5.3 Run the existing relevant Swift tests and release packaging checks for the changed surfaces.
- [x] 5.4 Confirm the change does not alter terminal input, keybinding, IME, or libghostty bridge behavior.
