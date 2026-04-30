## MODIFIED Requirements

### Requirement: Libghostty access is isolated behind one bridge
The system SHALL isolate all direct libghostty integration behind a single OpenMUX bridge capability with a stable internal interface, including vendored runtime bootstrap, hosted terminal surface creation, event translation, resize handling, and teardown.

#### Scenario: Upstream integration stays localized
- **WHEN** terminal-engine integration code is added or changed
- **THEN** vendored libghostty types and calls are confined to the bridge boundary

### Requirement: Bridge lifecycle owns terminal surface and session coordination
The terminal bridge SHALL define explicit ownership for vendored runtime bootstrap, hosted terminal surface creation, session attachment, focus activation, resize propagation, fallback coordination, and teardown.

#### Scenario: Runtime-host lifecycle has one owner
- **WHEN** a pane-backed terminal session is created, focused, resized, or destroyed
- **THEN** the bridge is the authoritative layer coordinating vendored runtime-hosted surface and session lifecycle transitions
