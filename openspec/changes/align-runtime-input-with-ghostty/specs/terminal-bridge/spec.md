## ADDED Requirements

### Requirement: The bridge exposes runtime selection through OpenMUX-native values
The terminal bridge SHALL expose runtime-owned terminal selection through OpenMUX-native data structures while keeping raw Ghostty selection and text types confined to `OmuxTerminalBridge`.

#### Scenario: Runtime selection read succeeds
- **WHEN** a hosted Ghostty surface has selected terminal text
- **THEN** the bridge SHALL return an OpenMUX-native selection value containing selected text and range metadata usable by the host view

#### Scenario: Runtime selection read is unavailable
- **WHEN** a hosted surface has no selection or the runtime cannot provide selection data
- **THEN** the bridge SHALL return no selection value without leaking Ghostty error details or raw Ghostty types

#### Scenario: Selection API does not leak Ghostty types
- **WHEN** app-shell code asks a terminal pane for selected text or range data
- **THEN** it SHALL consume only OpenMUX-native bridge values and SHALL NOT import `CGhostty`
