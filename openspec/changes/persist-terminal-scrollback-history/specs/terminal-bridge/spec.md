## ADDED Requirements

### Requirement: The bridge SHALL expose bounded terminal text snapshots
The terminal bridge SHALL expose bounded terminal text snapshots through OpenMUX-native abstractions and SHALL keep terminal-engine text extraction APIs confined to bridge-owned code.

#### Scenario: App shell requests scrollback without Ghostty types
- **WHEN** workspace persistence requests scrollback for a pane-backed terminal
- **THEN** it receives an OpenMUX-native bounded text snapshot or an explicit unavailable result without importing `CGhostty` or using raw terminal-engine types

#### Scenario: Snapshot failure is explicit
- **WHEN** the terminal runtime cannot provide text for a pane
- **THEN** the bridge returns an unavailable result instead of fabricating scrollback text
