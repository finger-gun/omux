## MODIFIED Requirements

### Requirement: Bridge lifecycle owns terminal surface and session coordination
The terminal bridge SHALL define explicit ownership for terminal surface creation, persistent PTY/session attachment, resize handling, output streaming, and teardown.

#### Scenario: Session lifecycle has one owner
- **WHEN** a pane-backed terminal session is created, resized, receives input, or is destroyed
- **THEN** the bridge is the authoritative layer coordinating surface and session lifecycle transitions

## ADDED Requirements

### Requirement: The bridge SHALL expose interactive terminal I/O through OpenMUX abstractions
The system SHALL let higher-level code send input to and observe output from live terminal sessions through OpenMUX-defined bridge abstractions rather than raw PTY or libghostty APIs.

#### Scenario: Shell code targets bridge-owned session I/O
- **WHEN** the app shell or control plane sends input to a pane-backed session
- **THEN** it does so through bridge operations defined in OpenMUX-native terms
