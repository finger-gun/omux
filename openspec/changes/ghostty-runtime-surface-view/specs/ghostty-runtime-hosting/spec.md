## ADDED Requirements

### Requirement: The pinned vendored Ghostty snapshot SHALL provide the runtime-hosting dependency
The system SHALL provide the Ghostty embedding dependency from the repository's pinned vendored snapshot so the runtime-hosted pane path can be built and inspected without relying on a machine-local Ghostty installation.

#### Scenario: Runtime-host build uses the pinned vendored dependency
- **WHEN** the terminal bridge is built with runtime-host support enabled
- **THEN** the build resolves the Ghostty embedding dependency from the pinned vendored snapshot in the repository

### Requirement: The bridge SHALL create native AppKit-hosted runtime pane surfaces through CGhostty
The system SHALL let `OmuxTerminalBridge` create a native AppKit-hosted pane surface through `CGhostty` for a pane that is attached to a live session, while keeping the containing workspace and pane-stack chrome in OpenMUX-owned shell code.

#### Scenario: Attached pane receives a native runtime host
- **WHEN** a pane-backed session is attached and the vendored runtime host is available
- **THEN** the bridge creates and returns a native AppKit-hosted libghostty-backed pane surface for that pane

### Requirement: Runtime-hosted panes SHALL remain behind OpenMUX-native bridge abstractions
The system SHALL keep vendored Ghostty app, surface, and host-view objects behind `OmuxTerminalBridge` so higher-level code continues to work in terms of OpenMUX-native panes, sessions, and normalized input.

#### Scenario: Shell code embeds a runtime host without raw Ghostty handles
- **WHEN** the app shell requests a hosted pane view
- **THEN** it receives a bridge-provided OpenMUX host view without direct access to raw vendored Ghostty objects
