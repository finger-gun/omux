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
