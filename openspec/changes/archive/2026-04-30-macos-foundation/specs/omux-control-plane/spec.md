## ADDED Requirements

### Requirement: The CLI controls the app through a local RPC contract
The system SHALL expose a local control plane between the OpenMUX desktop app and the `omux` CLI using JSON-RPC over a Unix domain socket.

#### Scenario: CLI operations use the public control boundary
- **WHEN** the `omux` CLI requests app-level behavior
- **THEN** it communicates through the local JSON-RPC control contract rather than private in-process coupling

### Requirement: Control-plane operations are capability-oriented
The control plane SHALL expose app operations in terms of OpenMUX capabilities such as opening workspaces, focusing panes, sending text, raising notifications, and restoring sessions.

#### Scenario: RPC commands map to OpenMUX behavior
- **WHEN** automation targets the desktop application
- **THEN** the available operations align with OpenMUX concepts instead of low-level terminal-engine details

### Requirement: The control plane remains local-first and lightweight
The system SHALL treat the app/CLI control plane as a local desktop boundary optimized for inspectability and minimal operational overhead.

#### Scenario: Local automation avoids unnecessary service complexity
- **WHEN** the control plane is used on a developer workstation
- **THEN** it does not require distributed-service infrastructure or unnecessary background processes beyond the local app service itself
