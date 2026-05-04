## ADDED Requirements

### Requirement: CLI reports installed OpenMUX version
The system SHALL provide an `omux version` command that reports the installed OpenMUX product version without requiring the desktop app to be running.

#### Scenario: Version command reports current version
- **WHEN** the user runs `omux version`
- **THEN** the CLI prints the current OpenMUX semantic version
- **AND** the command exits successfully

#### Scenario: Version command works offline
- **WHEN** the user runs `omux version` without network access
- **THEN** the CLI reports the locally installed version without querying a remote service

### Requirement: CLI discovers update availability from GitHub Releases
The system SHALL discover update availability from GitHub Release metadata for `finger-gun/omux` and compare the latest release version with the installed version using semantic version ordering.

#### Scenario: Newer release is available
- **WHEN** the latest GitHub Release version is greater than the installed version
- **THEN** the updater reports the available version and identifies the matching app archive asset

#### Scenario: Installed version is current
- **WHEN** the latest GitHub Release version is equal to or lower than the installed version
- **THEN** `omux update` reports that OpenMUX is already up to date
- **AND** it does not download or install an app archive

#### Scenario: Release metadata cannot be fetched
- **WHEN** the release metadata request fails
- **THEN** `omux update` exits with an explicit error
- **AND** it leaves the installed app unchanged

### Requirement: CLI verifies release assets before installation
The system SHALL download the selected OpenMUX app archive and release checksum file, verify the archive SHA-256 checksum, and refuse to install archives that cannot be verified.

#### Scenario: Checksum matches app archive
- **WHEN** the downloaded checksum file contains a SHA-256 entry for the downloaded app archive
- **AND** the computed archive checksum matches that entry
- **THEN** the updater may proceed to unarchive and validate the app bundle

#### Scenario: Checksum is missing
- **WHEN** the checksum file does not contain an entry for the selected app archive
- **THEN** `omux update` fails before unarchiving
- **AND** it leaves the installed app unchanged

#### Scenario: Checksum mismatches
- **WHEN** the computed archive checksum does not match the release checksum entry
- **THEN** `omux update` fails before unarchiving
- **AND** it leaves the installed app unchanged

### Requirement: CLI stages and validates updates in a per-user temporary directory
The system SHALL stage downloaded update artifacts in a per-user temporary directory, unarchive the app bundle there, and validate the staged app before prompting to close or replace any running app.

#### Scenario: Staged bundle is valid
- **WHEN** the archive unpacks to `OpenMUX.app`
- **AND** the staged bundle has the expected bundle identifier `dev.fingergun.omux`
- **AND** the staged bundle version matches the selected release version
- **THEN** the updater may prompt for installation

#### Scenario: Staged bundle is invalid
- **WHEN** the archive does not contain a valid `OpenMUX.app` for the selected release
- **THEN** `omux update` fails before prompting to close OpenMUX
- **AND** it leaves the installed app unchanged

#### Scenario: Temporary staging is cleaned
- **WHEN** an update completes or fails before helper handoff
- **THEN** the foreground updater removes temporary download and unarchive files that are no longer needed

### Requirement: CLI selects a writable app install target without hidden privilege escalation
The system SHALL install updates into the current OpenMUX app bundle path when that path can be determined and written, otherwise it SHALL choose a user-writable Applications location without invoking hidden privilege escalation.

#### Scenario: Existing app path is writable
- **WHEN** `omux update` determines the CLI belongs to an installed `OpenMUX.app`
- **AND** that app bundle location is writable by the current user
- **THEN** the updater targets that app bundle for replacement

#### Scenario: System Applications is not writable
- **WHEN** no current app bundle target is available
- **AND** `/Applications/OpenMUX.app` cannot be written by the current user
- **THEN** the updater targets `~/Applications/OpenMUX.app`
- **AND** it creates `~/Applications` if needed

#### Scenario: No writable target exists
- **WHEN** the updater cannot identify or create a writable app install target
- **THEN** `omux update` fails with a clear permissions message
- **AND** it does not ask to close OpenMUX

### Requirement: CLI prompts before closing a running OpenMUX app
The system SHALL ask for confirmation before closing a running OpenMUX app as part of an update install.

#### Scenario: User accepts close prompt
- **WHEN** OpenMUX is running and a staged update is ready to install
- **AND** the user accepts the close prompt or presses Return for the default affirmative answer
- **THEN** the updater proceeds to detached helper handoff

#### Scenario: User declines close prompt
- **WHEN** OpenMUX is running and a staged update is ready to install
- **AND** the user answers `n` or `N` to the close prompt
- **THEN** `omux update` cancels installation
- **AND** it leaves the running app and installed app unchanged

#### Scenario: OpenMUX is not running
- **WHEN** no OpenMUX app instance is running
- **THEN** `omux update` does not ask to close OpenMUX before installation

### Requirement: Detached helper completes app replacement independently
The system SHALL perform final app replacement from a detached helper process that does not execute from inside the app bundle being replaced.

#### Scenario: Helper replaces app after graceful termination
- **WHEN** the user confirms installation for a running OpenMUX app
- **THEN** the foreground updater starts a detached helper with absolute paths to the staged app, target app, backup path, and log path
- **AND** the helper asks OpenMUX to terminate gracefully
- **AND** the helper replaces the target app only after the running app exits

#### Scenario: Running app does not exit
- **WHEN** the helper asks OpenMUX to terminate
- **AND** OpenMUX does not exit within the bounded wait period
- **THEN** the helper aborts replacement
- **AND** the previous app remains installed

#### Scenario: Replacement fails
- **WHEN** the helper cannot place the staged app at the target location after moving the previous app aside
- **THEN** the helper restores the previous app from backup when possible
- **AND** records the failure in the update log

#### Scenario: Replacement succeeds
- **WHEN** the helper successfully places the staged app at the target location
- **THEN** the helper removes its temporary backup
- **AND** reopens the updated OpenMUX app
- **AND** cleans temporary staging files

### Requirement: App checks passively for update availability
The system SHALL check for update availability from the desktop app asynchronously after startup and at a conservative interval without blocking terminal startup, input, rendering, or workspace restoration.

#### Scenario: Startup check finds newer version
- **WHEN** OpenMUX starts
- **AND** the cached update-check interval allows a new check
- **AND** the latest release version is greater than the installed version
- **THEN** the app records update availability for that version

#### Scenario: Startup check fails
- **WHEN** the app-side release metadata request fails
- **THEN** OpenMUX continues startup and terminal use without presenting an error alert

#### Scenario: Check interval has not elapsed
- **WHEN** OpenMUX starts before the configured or built-in update-check interval has elapsed
- **THEN** the app does not perform another network update check

### Requirement: App surfaces update availability in workspace chrome
The system SHALL display update availability as an unobtrusive workspace chrome notice that tells the user which version is available and to run `omux update`.

#### Scenario: Update notice is shown
- **WHEN** the app has recorded that a newer OpenMUX version is available
- **THEN** the workspace sidebar footer shows the available version
- **AND** the notice includes the command `omux update`

#### Scenario: No update notice when current
- **WHEN** no newer release is known
- **THEN** the workspace sidebar does not show an update notice

#### Scenario: Update notice does not affect terminal input
- **WHEN** the update notice is visible
- **THEN** terminal panes continue to receive keyboard input according to the existing input pipeline
- **AND** no keybindings, dead-key handling, Option-key behavior, or IME behavior changes

### Requirement: Self-update avoids new long-running services
The system SHALL implement update checking and installation without introducing a persistent daemon, launch agent, browser shell, or libghostty bridge dependency.

#### Scenario: App is idle after update check
- **WHEN** an app-side update check completes
- **THEN** no updater daemon or helper process remains running

#### Scenario: Terminal bridge remains isolated
- **WHEN** update discovery, notification, or installation runs
- **THEN** it does not import or expose libghostty-specific types
