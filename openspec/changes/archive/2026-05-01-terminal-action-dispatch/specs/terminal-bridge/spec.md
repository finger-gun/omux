## ADDED Requirements

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

