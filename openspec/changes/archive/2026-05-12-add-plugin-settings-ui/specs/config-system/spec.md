## ADDED Requirements

### Requirement: Config CLI SHALL expose effective config as JSON
The `omux config get --json` command SHALL return the current effective OpenMUX configuration and diagnostics in a structured JSON format suitable for scripts and plugins.

#### Scenario: Config get succeeds
- **WHEN** the user runs `omux config get --json`
- **THEN** the command prints structured JSON containing supported effective config values, source file path, defaults metadata where available, and diagnostics

#### Scenario: Config has diagnostics
- **WHEN** the current config has warnings or errors
- **THEN** the JSON output includes those diagnostics with severity, message, file path, and line number when available

### Requirement: Config CLI SHALL apply supported config changes from JSON
The `omux config apply` command SHALL accept a structured JSON file containing supported OpenMUX-owned config changes, validate the resulting configuration, atomically update `~/.omux/config.toml`, and trigger the standard reload path after successful writes.

#### Scenario: Apply valid config changes
- **WHEN** the user runs `omux config apply --json-file <path>` with valid supported settings
- **THEN** OpenMUX writes the changes to `~/.omux/config.toml`, reloads configuration, and reports success

#### Scenario: Apply invalid config changes
- **WHEN** the JSON file contains invalid values or unsupported keys
- **THEN** OpenMUX leaves `~/.omux/config.toml` unchanged and reports structured diagnostics

#### Scenario: Apply preserves unedited settings
- **WHEN** the existing config contains settings not present in the apply payload
- **THEN** OpenMUX preserves those settings while updating only supported requested values

### Requirement: Config writes SHALL be recoverable
Config apply operations SHALL write through an atomic replacement path and preserve a backup of the previous config before replacing it.

#### Scenario: Write succeeds
- **WHEN** config apply replaces the config file
- **THEN** the previous file is recoverable from an OpenMUX-managed backup location

#### Scenario: Write fails
- **WHEN** config apply cannot complete the write
- **THEN** OpenMUX preserves the previous config file and reports the filesystem error
