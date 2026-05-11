## ADDED Requirements

### Requirement: Control plane SHALL expose palette-discoverable CLI command metadata
The control plane and `omux` CLI SHALL expose explicit metadata for supported CLI commands that are safe to discover and invoke from command palette command mode without collecting additional arguments. Built-in safe-default CLI command metadata MAY be declared in bundled JSON descriptors with typed `command.kind` and `command.target` fields.

#### Scenario: Palette discovers supported CLI commands
- **WHEN** command mode requests supported `omux` CLI commands
- **THEN** OpenMUX returns command identifiers, titles, categories, descriptions, aliases, argument requirements, enabled state, and invocation targets for commands that are palette-invokable with no arguments or safe focused/default targets

#### Scenario: Descriptor CLI target is allowlisted
- **WHEN** a bundled descriptor declares `command.kind` as `builtin`
- **THEN** OpenMUX exposes the command only if `command.target` maps to a supported typed control operation

#### Scenario: Unsupported CLI command is hidden
- **WHEN** an `omux` CLI command lacks an explicit palette-invokable metadata contract
- **THEN** the command palette does not show or execute that command

#### Scenario: Argument-requiring CLI command is hidden
- **WHEN** an `omux` CLI command requires freeform text, a file path, or an explicit selector with no safe default
- **THEN** the command palette does not show or execute that command in v1

### Requirement: Palette CLI invocations SHALL use the public control boundary
CLI-backed command palette selections SHALL invoke supported behavior through the same typed action/control APIs behind the local control-plane contract rather than constructing arbitrary shell command strings, spawning the `omux` executable, or looping back through JSON-RPC from inside the app.

#### Scenario: Palette invokes supported CLI operation
- **WHEN** the user selects a CLI-backed command result from command mode
- **THEN** OpenMUX invokes the corresponding typed control operation with explicit OpenMUX-native arguments

#### Scenario: Palette does not spawn omux subprocess
- **WHEN** the app invokes a CLI-backed palette command
- **THEN** OpenMUX does not spawn the `omux` executable as a subprocess and does not call its own JSON-RPC socket as a loopback client

#### Scenario: Palette does not execute arbitrary shell text
- **WHEN** a palette query resembles an unsupported shell command or arbitrary `omux` command string
- **THEN** OpenMUX treats it as search text and does not execute it as shell input or a subprocess

#### Scenario: Descriptor command field is not bash
- **WHEN** a descriptor contains a `command` object
- **THEN** OpenMUX interprets it as typed metadata and does not pass its fields to a shell interpreter
