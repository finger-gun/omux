## Why

OpenMUX releases currently require users to visit GitHub manually, download an archive, unarchive it, and move the app bundle themselves. A terminal-first workspace should make staying current possible from the same `omux` tool users already rely on, while still keeping release discovery and installation explicit, inspectable, and lightweight.

## Goals

- Provide a first-party `omux version` command that reports the installed OpenMUX version.
- Provide a first-party `omux update` command that discovers the latest GitHub Release, verifies the archived app asset, stages it safely, and installs `OpenMUX.app` on the user's behalf.
- Allow `omux update` to prompt before closing a running OpenMUX app, then hand off to a detached helper so the update can continue even if the command was launched from an OpenMUX terminal session.
- Let the app check for newer releases asynchronously and surface an unobtrusive workspace-sidebar notification telling the user which version is available and to run `omux update`.
- Keep the mechanism macOS-native, local-first, and explicit; do not introduce a daemon, browser shell, or vendor-specific package manager dependency.

## Non-goals

- Automatic background installation without user confirmation.
- Silent forced app termination or data-loss-prone session shutdown.
- Admin privilege escalation, hidden `sudo`, or system-wide installers.
- Replacing future notarized DMG/Homebrew distribution; this change supports the current GitHub archive flow and should remain compatible with later signed artifacts.
- Any change to terminal input, keyboard handling, or the libghostty bridge.

## What Changes

- Add `omux version` to print the current product version from the installed CLI/app metadata.
- Add `omux update` to fetch latest release metadata, download the expected OpenMUX app archive and checksum file, verify integrity, unarchive into a per-user temporary staging directory, validate the staged bundle, and install it into the selected Applications directory.
- Add an interactive prompt when a running OpenMUX instance must close before app replacement, with a default affirmative answer such as `Close OpenMUX to install 0.5.0? [Y/n]`.
- Add detached update handoff behavior so replacing `OpenMUX.app` does not depend on a process executing from the bundle being replaced.
- Add app-side update availability checks on startup and at a conservative interval, with cached check timestamps to avoid unnecessary network traffic.
- Add a sidebar/footer update notice that displays the available version and the command to run, e.g. `New version 0.5.0 - run: omux update`.
- Strengthen release artifact requirements so GitHub Releases publish predictable app archive names and SHA-256 checksums that the updater can consume.

## Capabilities

### New Capabilities

- `self-update`: Covers CLI version reporting, release discovery, verified app archive download/staging, prompted app replacement, detached helper handoff, and app-side update availability notifications.

### Modified Capabilities

- `release-changelog-workflow`: Require tag-triggered GitHub Releases to publish predictable app archive and checksum assets suitable for verification by the self-update command.

## Impact

- Affects `Sources/OmuxCLI` for new `version` and `update` commands, release metadata fetching, checksum verification, staging, and detached install handoff.
- Affects app-shell startup/UI code for periodic update checks and sidebar notification rendering.
- Affects release packaging/specification expectations around app archive naming and checksum availability.
- May add focused tests for version output, release metadata parsing, update eligibility, checksum validation, bundle validation, prompt behavior, and update notification state.
- Does not affect keyboard/input correctness, plugin APIs, or the libghostty bridge boundary. The update check should remain outside terminal rendering and input paths.
