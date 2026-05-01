# omux-control-plane Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.
## Requirements
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

### Requirement: Terminal event contracts are defined in OpenMUX-native control-plane terms
The control plane SHALL define terminal event names and payload shapes in OpenMUX-native terms for local automation and future event delivery surfaces. These event contracts SHALL avoid Ghostty-specific enums, tags, and payload structs.

#### Scenario: Control-plane terminal event names are product-level contracts
- **WHEN** OpenMUX defines a control-plane event for terminal cwd, command completion, progress, or renderer health
- **THEN** the event name and payload shape are expressed in OpenMUX-native terms instead of Ghostty callback identifiers

#### Scenario: Terminal event semantics are transport-independent
- **WHEN** the local control plane evolves from request/response commands to include event publication in a future change
- **THEN** terminal event meanings and payload fields remain stable because they were defined independently of a specific streaming transport
