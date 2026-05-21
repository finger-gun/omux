## ADDED Requirements

### Requirement: Hosted terminal surface visibility SHALL be independent from session liveness
The system SHALL track hosted terminal surface presentation visibility separately from the liveness of the attached terminal session, PTY, and child process.

#### Scenario: Hidden surface keeps session alive
- **WHEN** a terminal pane belongs to an inactive workspace, inactive tab, inactive pane-stack tab, hidden floating modal, minimized window, or occluded window
- **THEN** OpenMUX marks the hosted terminal surface as not user-visible without terminating, detaching, or restarting its terminal session

#### Scenario: Hidden surface keeps terminal events alive
- **WHEN** a non-visible terminal session emits output, title changes, progress reports, bells, or child-process lifecycle events
- **THEN** OpenMUX continues to process those events according to existing terminal, hook, persistence, and control-plane contracts

### Requirement: Hosted terminal surfaces SHALL quiesce presentation work while hidden
The terminal bridge SHALL expose an OpenMUX-native visibility operation for hosted terminal surfaces and SHALL map that operation to terminal-engine presentation quiescing inside the bridge implementation.

#### Scenario: Hidden surface is marked occluded through the bridge
- **WHEN** app-shell state determines a hosted terminal surface is not user-visible
- **THEN** the app shell calls an OpenMUX terminal-bridge visibility API rather than calling libghostty APIs directly

#### Scenario: Bridge localizes terminal-engine occlusion
- **WHEN** the runtime implementation supports an upstream occlusion or visibility primitive
- **THEN** only the terminal bridge maps OpenMUX visibility to that upstream primitive

#### Scenario: Visible surface is refreshed after unocclusion
- **WHEN** a previously hidden hosted terminal surface becomes user-visible
- **THEN** OpenMUX marks it visible through the bridge and refreshes presentation so current terminal output is shown without restarting the session

### Requirement: App focus SHALL remain distinct from surface focus
The terminal bridge SHALL treat application/window focus and individual surface focus as distinct lifecycle signals.

#### Scenario: Unfocusing one pane does not unfocus the app
- **WHEN** one terminal pane loses pane focus while another terminal pane or the OpenMUX window remains active
- **THEN** OpenMUX does not report the entire terminal application runtime as unfocused solely because that pane lost focus

#### Scenario: Hidden surface is not an input target
- **WHEN** a hosted terminal surface is not user-visible
- **THEN** OpenMUX does not route keyboard input to that surface until it becomes visible and focused again
