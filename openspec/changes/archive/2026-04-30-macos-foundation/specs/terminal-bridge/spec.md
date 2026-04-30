## ADDED Requirements

### Requirement: Libghostty access is isolated behind one bridge
The system SHALL isolate all direct libghostty integration behind a single OpenMUX bridge capability with a stable internal interface.

#### Scenario: Upstream integration stays localized
- **WHEN** terminal-engine integration code is added or changed
- **THEN** direct libghostty types and calls are confined to the bridge boundary

### Requirement: OpenMUX uses native domain objects outside the bridge
The system SHALL expose OpenMUX-native concepts such as panes, sessions, surfaces, and key events outside the terminal bridge instead of leaking upstream implementation details.

#### Scenario: App code consumes bridge abstractions
- **WHEN** app or CLI code interacts with terminal-backed behavior
- **THEN** it does so through OpenMUX-defined interfaces rather than raw libghostty APIs

### Requirement: Bridge lifecycle owns terminal surface and session coordination
The terminal bridge SHALL define explicit ownership for terminal surface creation, PTY/session attachment, and teardown.

#### Scenario: Session lifecycle has one owner
- **WHEN** a pane-backed terminal session is created or destroyed
- **THEN** the bridge is the authoritative layer coordinating surface and session lifecycle transitions
