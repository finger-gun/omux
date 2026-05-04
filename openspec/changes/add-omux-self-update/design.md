## Context

OpenMUX currently publishes GitHub Release assets that users install manually. The release workflow already emits an app archive, a CLI archive, and checksums, and the app bundle already includes a bundled `omux` executable. The missing piece is a first-party update path that can be driven from the terminal without turning OpenMUX into a background service or package-manager-specific product.

The most delicate case is when `omux update` is launched from a terminal pane inside OpenMUX. If the CLI asks the app to quit before the installer is detached, the terminal session can disappear and interrupt the update. The updater therefore needs to finish network/staging work first, then transfer the final replacement step to a process that is independent of the running app bundle and terminal session.

Temporary staging is appropriate on macOS for all normal user setups when created through the system-provided per-user temporary directory. The updater must keep absolute paths, validate staged contents before prompting to close the app, and clean up after success or failure.

## Goals / Non-Goals

**Goals:**

- Report the installed OpenMUX version through `omux version`.
- Discover newer releases from GitHub Release metadata rather than scraping HTML.
- Download, checksum, unarchive, and validate the app archive before replacing any installed app.
- Support installs under `/Applications` and user-owned locations such as `~/Applications` without hidden privilege escalation.
- Prompt before closing OpenMUX, then use a detached helper so replacement can continue after the app exits.
- Surface update availability in the app without blocking startup, terminal input, or rendering.

**Non-Goals:**

- Automatic or silent update installation.
- Admin authorization prompts, hidden `sudo`, or privileged helper tools.
- A long-running update daemon.
- Changing terminal input behavior, keybindings, or the libghostty bridge.
- Replacing later notarized DMG/Homebrew distribution paths.

## Decisions

### Use GitHub Releases API as the discovery source

`omux update` and the app-side checker should call `https://api.github.com/repos/finger-gun/omux/releases/latest` and parse release JSON for `tag_name` and assets. This is more stable than scraping the GitHub Releases page and better reflects the actual downloadable artifacts than reading `main/VERSION`.

Alternatives considered:

- Scrape `https://github.com/finger-gun/omux/releases`: brittle HTML dependency.
- Read `main/VERSION`: easy, but it can lead released users toward unreleased main-branch versions and does not provide asset URLs.
- Add a custom update manifest now: cleaner long-term, but unnecessary while GitHub Releases already contain metadata and assets.

### Keep version resolution explicit and package-aware

Add a small OpenMUX-owned version provider used by both CLI and app. It should prefer `CFBundleShortVersionString` when running from `OpenMUX.app`, fall back to an embedded/release-packaged `VERSION` resource for standalone CLI archives, and support repository-local `VERSION` during development.

Alternatives considered:

- Hardcode the version in Swift source for every release: simple but easy to forget during release preparation.
- Query GitHub for current version: incorrect offline and not the installed version.

### Stage all update work before prompting to close OpenMUX

The foreground `omux update` command should complete release discovery, download, checksum verification, unarchive, bundle validation, and target writability checks before asking the user to close the app. The prompt should appear only when the update is ready to install.

Alternatives considered:

- Prompt before download: simpler flow, but users could close OpenMUX only to hit a network or checksum failure.
- Close app immediately and let a helper do everything: riskier UX and harder to report recoverable failures.

### Use a copied detached CLI helper for final replacement

For the final install step, copy the current `omux` executable to the staging directory and spawn it in a detached/nohup-style process with an internal helper command and a manifest path. The helper should not execute from inside `OpenMUX.app`, so replacing the app bundle does not invalidate the running installer.

The helper owns:

1. Gracefully terminating running OpenMUX instances by bundle identifier.
2. Waiting for the target app process to exit within a bounded timeout.
3. Replacing the app bundle with rollback on failure.
4. Reopening the updated app when replacement succeeds.
5. Writing progress/failure details to a temp log path printed by the foreground command.
6. Cleaning the staging directory when done.

Alternatives considered:

- Temporary shell script only: survives app replacement, but process detection and rollback logic are more fragile and harder to test.
- Run the bundled `omux` directly: unsafe when the bundle containing that executable is the thing being replaced.
- Dedicated privileged helper: unnecessary and too heavyweight for unsigned archive installs.

### Install target selection should respect the current install

When the running CLI can determine it came from an installed `OpenMUX.app`, the update should target that app bundle path. Otherwise it should prefer `/Applications/OpenMUX.app` when writable and fall back to `~/Applications/OpenMUX.app` when not. The command may expose an explicit target option later, but the first implementation should avoid hidden escalation.

Alternatives considered:

- Always target `/Applications`: fails on common non-admin or user-local setups.
- Always target `~/Applications`: surprising for users who installed in `/Applications`.
- Ask every time: explicit but noisy for a common update path.

### App-side checks are passive and cached

The app should perform update availability checks asynchronously after launch and on a conservative interval. A failed check should not affect startup or terminal use. The notification belongs in the workspace/sidebar chrome, not in terminal rendering.

Alternatives considered:

- Check synchronously during launch: harms startup performance.
- Background daemon or launch agent: unnecessary service complexity.
- System notification only: less discoverable and does not show the terminal-native `omux update` path.

## Risks / Trade-offs

- [GitHub API unavailable or rate-limited] -> Treat as a non-fatal explicit update-check failure in CLI and a silent/no-notice app-side miss; never block startup.
- [Checksum missing or mismatched] -> Abort before unarchive/install and leave the current app untouched.
- [Staged app is malformed or wrong bundle ID] -> Abort before prompt and leave the current app untouched.
- [Target app location is not writable] -> Fall back to `~/Applications` when target selection allows it, otherwise fail with a clear message; do not invoke `sudo`.
- [OpenMUX does not terminate within timeout] -> Abort replacement and tell the user to quit OpenMUX manually, preserving the staged update only long enough for diagnostics.
- [Replacement fails after old app is moved aside] -> Restore the previous app bundle from backup and report the helper log path.
- [Update prompt from inside OpenMUX closes the terminal that launched it] -> The detached copied helper continues independently, and the foreground command prints that OpenMUX will quit and where progress is logged.
- [Unsigned archive remains a Gatekeeper limitation] -> This change verifies integrity against release checksums but does not claim notarization; future signed DMG/Homebrew flows can reuse discovery/version logic.

## Migration Plan

1. Add version resolution and release metadata parsing without changing existing release behavior.
2. Add `omux version` and test it for app-bundled, standalone, and development contexts.
3. Add `omux update` in an explicit, user-driven path.
4. Add passive app-side update checks and sidebar notification rendering.
5. Tighten release packaging/specs so future releases always include predictable app archive and checksum assets.

Rollback is straightforward before an update is installed because the current app is untouched until the detached helper runs. During install, the helper should keep a temporary backup of the previous app bundle until the new bundle is in place and validated, then restore that backup if replacement fails.

## Open Questions

- Should the first implementation expose an explicit `omux update --target <path>` option, or defer that until user-local installs need more control?
- Should the helper relaunch OpenMUX by default after successful update, or should relaunch become a prompt/flag?
- Should app-side update checks be configurable in `~/.omux/config.toml`, or is a built-in conservative interval sufficient for the first version?
