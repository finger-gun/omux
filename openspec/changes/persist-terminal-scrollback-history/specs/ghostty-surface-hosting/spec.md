## ADDED Requirements

### Requirement: Hosted Ghostty surfaces SHALL provide bounded scrollback through the bridge
Hosted Ghostty surfaces SHALL support bounded scrollback capture through `OmuxTerminalBridge` without transferring surface ownership or raw `libghostty` access to the app shell.

#### Scenario: Surface text capture stays bridge-owned
- **WHEN** OpenMUX captures scrollback for a Ghostty-hosted pane
- **THEN** direct calls to Ghostty text APIs occur only inside the terminal bridge module

#### Scenario: Surface lifecycle remains unchanged
- **WHEN** scrollback is captured for persistence
- **THEN** the hosted surface remains owned by the bridge and its live session lifecycle is not restarted or torn down for capture
