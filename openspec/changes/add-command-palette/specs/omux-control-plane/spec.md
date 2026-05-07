## ADDED Requirements

### Requirement: Control plane SHALL expose palette-discoverable CLI command metadata
The control plane and `omux` CLI SHALL expose explicit metadata for supported CLI commands that are safe to discover and invoke from command palette command mode.

#### Scenario: Palette discovers supported CLI commands
- **WHEN** command mode requests supported `omux` CLI commands
- **THEN** OpenMUX returns command identifiers, titles, categories, descriptions, argument requirements, enabled state, and invocation targets for commands that are palette-invokable

#### Scenario: Unsupported CLI command is hidden
- **WHEN** an `omux` CLI command lacks an explicit palette-invokable metadata contract
- **THEN** the command palette does not show or execute that command

### Requirement: Palette CLI invocations SHALL use the public control boundary
CLI-backed command palette selections SHALL invoke supported behavior through the local control-plane contract rather than constructing arbitrary shell command strings.

#### Scenario: Palette invokes supported CLI operation
- **WHEN** the user selects a CLI-backed command result from command mode
- **THEN** OpenMUX invokes the corresponding local JSON-RPC control-plane operation with explicit OpenMUX-native arguments

#### Scenario: Palette does not execute arbitrary shell text
- **WHEN** a palette query resembles an unsupported shell command or arbitrary `omux` command string
- **THEN** OpenMUX treats it as search text and does not execute it as shell input or a subprocess
