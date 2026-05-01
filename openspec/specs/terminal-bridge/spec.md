# terminal-bridge Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.

## Requirements

### Requirement: Libghostty access is isolated behind one bridge
The system SHALL isolate all direct libghostty integration behind a single OpenMUX bridge capability with a stable internal interface, including hosted terminal surface creation, event translation, resize handling, and teardown.

#### Scenario: Upstream integration stays localized
- **WHEN** terminal-engine integration code is added or changed
- **THEN** direct libghostty types and calls are confined to the bridge boundary

### Requirement: OpenMUX uses native domain objects outside the bridge
The system SHALL expose OpenMUX-native concepts such as panes, sessions, surfaces, and key events outside the terminal bridge instead of leaking upstream implementation details, even when the pane is backed by a live libghostty-hosted surface.

#### Scenario: App code consumes bridge abstractions
- **WHEN** app or CLI code interacts with terminal-backed behavior
- **THEN** it does so through OpenMUX-defined interfaces rather than raw libghostty APIs

### Requirement: Bridge lifecycle owns terminal surface and session coordination
The terminal bridge SHALL define explicit ownership for hosted terminal surface creation, PTY/session attachment, focus activation, resize propagation, fallback coordination, and teardown.

#### Scenario: Session lifecycle has one owner
- **WHEN** a pane-backed terminal session is created, focused, resized, or destroyed
- **THEN** the bridge is the authoritative layer coordinating hosted surface and session lifecycle transitions

### Requirement: The bridge SHALL expose interactive terminal I/O through OpenMUX abstractions
The system SHALL let higher-level code send input to and observe output from live terminal sessions through OpenMUX-defined bridge abstractions rather than raw PTY or libghostty APIs.

#### Scenario: Shell code targets bridge-owned session I/O
- **WHEN** the app shell or control plane sends input to a pane-backed session
- **THEN** it does so through bridge operations defined in OpenMUX-native terms

### Requirement: The bridge loads a host-supplied compiled Ghostty configuration
The terminal bridge SHALL accept a path to a compiled Ghostty configuration file from the OpenMUX host during initialization, load it via the public libghostty configuration API, finalize it, and use the resulting configuration for all engine sessions. The bridge SHALL NOT initialize the engine on a blank or default-only configuration once a host configuration is available.

#### Scenario: Bridge initializes with compiled config
- **WHEN** the host calls the bridge initialization with a valid path produced by the OpenMUX theme compiler
- **THEN** the bridge calls `ghostty_config_new`, loads the file via `ghostty_config_load_file`, calls `ghostty_config_finalize`, and creates the engine app with the resulting configuration

#### Scenario: Bridge surfaces load failure
- **WHEN** the supplied path does not exist or cannot be parsed by the engine
- **THEN** the bridge surfaces a structured diagnostic to the host and does not silently fall back to defaults

### Requirement: The bridge MUST NOT read the user's Ghostty configuration files
The terminal bridge SHALL NOT call `ghostty_config_load_default_files`, SHALL NOT open files under the user's Ghostty configuration paths, and SHALL NOT pass any path under those locations to libghostty configuration loaders. This rule SHALL be verifiable by automated inspection of the bridge module.

#### Scenario: Default-files loader is never called
- **WHEN** the bridge module source is inspected
- **THEN** no call site references `ghostty_config_load_default_files`

#### Scenario: User Ghostty config is invisible to the bridge
- **WHEN** a user has a populated `~/.config/ghostty/config` and runs OpenMUX
- **THEN** the engine behavior is unchanged compared to running with the same `~/.config/ghostty/config` absent

### Requirement: The bridge surfaces engine diagnostics as OpenMUX-native diagnostics
The terminal bridge SHALL collect Ghostty configuration diagnostics via `ghostty_config_diagnostics_count` and `ghostty_config_get_diagnostic` after each load and finalize, translate them into OpenMUX-native diagnostic structures, and return them to the host. Hosts and CLI tools SHALL consume only the OpenMUX-native form.

#### Scenario: Engine diagnostics translated
- **WHEN** the engine reports one or more configuration diagnostics during finalization
- **THEN** the bridge returns an array of OpenMUX-native diagnostics carrying severity, message, and (when available) location, with no Ghostty types in the returned data

#### Scenario: No diagnostics
- **WHEN** the engine reports zero diagnostics
- **THEN** the bridge returns an empty diagnostics array and the host treats the load as fully successful

### Requirement: The bridge supports live configuration refresh without session restart
The terminal bridge SHALL accept a refreshed compiled configuration path from the host at any time after initialization, build a new configuration object, finalize it, apply it via `ghostty_app_update_config`, free the previous configuration, and SHALL NOT recreate or terminate any existing terminal session as part of the refresh.

#### Scenario: Refresh keeps sessions alive
- **WHEN** the host calls the bridge refresh entry point with a new valid path while terminal sessions are running
- **THEN** the engine adopts the new configuration, all running sessions continue without interruption, and PTY processes are not restarted

#### Scenario: Refresh failure preserves previous configuration
- **WHEN** the host supplies a refreshed path that fails to load or finalize
- **THEN** the bridge surfaces diagnostics to the host, retains the previously-applied configuration, and existing sessions continue under that previous configuration

### Requirement: The bridge emits typed terminal action events for supported runtime actions
The terminal bridge SHALL decode supported runtime action callbacks and emit typed OpenMUX-native terminal action events keyed to the affected pane and session. The bridge SHALL keep Ghostty callback details and Ghostty action payload types confined to bridge-owned code.

#### Scenario: Bridge emits pane-scoped terminal action event
- **WHEN** a hosted Ghostty surface emits a supported action callback
- **THEN** the bridge emits a terminal action event that identifies the corresponding OpenMUX pane and session and includes only OpenMUX-native payload values

#### Scenario: Bridge action translation does not leak Ghostty callback types
- **WHEN** code outside `OmuxTerminalBridge` observes a dispatched terminal action
- **THEN** it can do so without importing `CGhostty` or referencing Ghostty callback enums or structs

### Requirement: The bridge keeps unsupported and app-shell actions rejected by default
The terminal bridge SHALL continue to reject unsupported actions and Ghostty app-shell ownership requests by default while honoring only the explicitly supported first-wave action set.

#### Scenario: Bridge rejects unsupported action
- **WHEN** the runtime emits an action outside the supported first-wave action set
- **THEN** the bridge leaves the action unhandled unless a later change explicitly adds OpenMUX-native support for it

#### Scenario: Bridge rejects app-target shell ownership request
- **WHEN** the runtime emits an app-target Ghostty action for window, tab, split, fullscreen, config, or update behavior
- **THEN** the bridge rejects that action and preserves OpenMUX ownership of shell behavior
