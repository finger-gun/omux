## ADDED Requirements

### Requirement: Control plane SHALL expose pane-status reporting for tool adapters
The control plane SHALL expose a local pane-status operation that accepts an explicit OpenMUX-native terminal target, normalized status state, optional progress value, optional label, optional message, and optional source identifier.

#### Scenario: Adapter targets exact pane
- **WHEN** an adapter reports pane status with a pane ID target
- **THEN** the control plane applies the status to that exact pane if it resolves to a live terminal session

#### Scenario: Adapter targets focused pane
- **WHEN** an adapter reports pane status with a focused target
- **THEN** the control plane applies the status to the terminal currently receiving keyboard input

#### Scenario: Invalid target fails explicitly
- **WHEN** an adapter reports pane status for a target that cannot resolve to a live terminal session
- **THEN** the control plane returns a structured failure instead of silently applying status to another pane

### Requirement: CLI SHALL expose pane-status for scripts and plugins
The `omux` CLI SHALL expose pane-status reporting through a command suitable for shell scripts, hook handlers, and plugin adapters.

#### Scenario: CLI accepts normalized status states
- **WHEN** a script runs `omux pane-status --pane <id> --state needs-input --source adapter.codex`
- **THEN** the CLI sends a pane-status request through the local control plane with the normalized state and source metadata

#### Scenario: CLI supports ergonomic state aliases
- **WHEN** a script reports aliases such as `running`, `active`, `done`, `completed`, `failed`, or `input`
- **THEN** the CLI maps them to the normalized pane-status states before sending the control-plane request

#### Scenario: CLI clamps progress values
- **WHEN** a script reports a numeric status value outside the supported progress range
- **THEN** the CLI clamps or rejects the value consistently before sending the control-plane request

### Requirement: Pane-status reporting SHALL remain local and OpenMUX-native
Pane-status reporting SHALL use the local control plane and OpenMUX-native identifiers rather than remote services, vendor SDKs, or terminal-engine private identifiers.

#### Scenario: Adapter does not need Ghostty surface ID
- **WHEN** an adapter reports status for a pane
- **THEN** it uses pane, session, tab, workspace, or focused selectors rather than a Ghostty runtime surface ID

#### Scenario: Reporting does not require network access
- **WHEN** an adapter reports status to OpenMUX
- **THEN** it communicates with the local app control plane and does not require a remote service
