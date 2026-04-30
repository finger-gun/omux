# config-system Specification

## Purpose
Define the OpenMUX-owned configuration surface, diagnostics, and Ghostty pass-through boundary.

## Requirements

### Requirement: OpenMUX owns its user-facing configuration file
The system SHALL store user-facing configuration in a single TOML file at `~/.omux/config.toml`. The file is the only configuration surface OpenMUX reads from disk for its own settings. The system MUST NOT read the user's Ghostty configuration files (e.g. `~/.config/ghostty/config`, `~/Library/Application Support/com.mitchellh.ghostty/config`) for any purpose at runtime.

#### Scenario: Config file is loaded on launch
- **WHEN** OpenMUX starts and `~/.omux/config.toml` exists
- **THEN** the system parses it as TOML and applies its values to OpenMUX behavior

#### Scenario: Config file is absent on launch
- **WHEN** OpenMUX starts and `~/.omux/config.toml` does not exist
- **THEN** the system runs on documented built-in defaults and does not auto-create the file

#### Scenario: Ghostty user config is never read
- **WHEN** OpenMUX initializes the terminal engine for any session
- **THEN** the bridge does not call `ghostty_config_load_default_files` and does not open any path under the user's Ghostty config locations

### Requirement: Configuration is schema-versioned
The system SHALL require every `~/.omux/config.toml` file to declare a top-level `schema` integer. The loader SHALL accept the schema version it was built to understand, MAY apply documented one-shot migrations for older versions, and SHALL refuse newer versions with a clear diagnostic.

#### Scenario: Current schema loads cleanly
- **WHEN** the file declares the schema version this build understands
- **THEN** the loader accepts the file without warnings about schema

#### Scenario: Future schema is rejected
- **WHEN** the file declares a schema version newer than this build understands
- **THEN** the loader emits a hard-error diagnostic naming both the file's schema and the build's supported schema, and configuration falls back to defaults

#### Scenario: Missing schema field is rejected
- **WHEN** the file does not declare a `schema` field at all
- **THEN** the loader emits a hard-error diagnostic instructing the user to add `schema = 1`

### Requirement: Built-in defaults are layered under the user file
The system SHALL resolve effective configuration by starting from documented built-in defaults and overlaying user file values on top of them. Any key the user does not set takes its built-in default. The system SHALL NOT require the user to provide a complete configuration file.

#### Scenario: Partial user file
- **WHEN** the user file sets only `[theme] name = "dracula"`
- **THEN** the active theme is `dracula` and every other setting takes its built-in default

#### Scenario: Empty user file
- **WHEN** the user file contains only `schema = 1` and no other keys
- **THEN** the system runs identically to having no file at all, except the file is treated as schema-versioned

### Requirement: Configuration loader emits structured diagnostics
The system SHALL surface configuration parse errors, validation errors, and warnings as structured diagnostics that include severity, message, file path, and (when available) line number. Diagnostics SHALL be observable both at launch time and via an `omux config doctor` CLI command.

#### Scenario: Parse error names the line
- **WHEN** the user file contains a TOML syntax error on line 12
- **THEN** the diagnostic identifies the file path, the line number, and a human-readable description of the syntax error

#### Scenario: doctor command reports current state
- **WHEN** the user runs `omux config doctor`
- **THEN** the command prints all current diagnostics, exits zero if all are warnings, and exits non-zero if any are hard errors

### Requirement: Configuration changes are loaded live
The system SHALL detect changes to `~/.omux/config.toml` and to the active theme file, recompile the effective configuration, and apply the result without restarting terminal sessions. The system SHALL also expose an explicit `omux config reload` command that performs the same recompile-and-apply on demand.

#### Scenario: Edit triggers reload
- **WHEN** the user saves a change to `~/.omux/config.toml` while OpenMUX is running
- **THEN** the system recompiles, applies the new configuration, and existing terminal sessions remain alive

#### Scenario: Failed reload preserves last good config
- **WHEN** an edit produces a configuration that fails validation
- **THEN** diagnostics are surfaced and the previous successfully-applied configuration remains active

#### Scenario: Explicit reload command
- **WHEN** the user runs `omux config reload`
- **THEN** the system performs the same recompile-and-apply pass independent of any file watcher state

### Requirement: A `[ghostty]` pass-through is permanently available
The system SHALL accept a top-level `[ghostty]` table in `~/.omux/config.toml` whose keys are forwarded into the generated Ghostty configuration. The system SHALL NOT enforce a key allowlist or blocklist on `[ghostty]`. The system SHALL document `[ghostty]` as an advanced escape hatch whose keys are not OpenMUX-versioned.

#### Scenario: Pass-through key reaches the engine
- **WHEN** the user sets `"copy-on-select" = false` under `[ghostty]`
- **THEN** the generated Ghostty configuration contains `copy-on-select = false` and the engine honors it

#### Scenario: Unknown pass-through key is forwarded
- **WHEN** the user sets a key under `[ghostty]` that this OpenMUX build has never heard of
- **THEN** the key is forwarded to Ghostty unchanged and any resulting Ghostty diagnostic is surfaced to the user

### Requirement: OpenMUX-managed keys override `[ghostty]` pass-through
The system SHALL maintain a documented list of Ghostty configuration keys it manages from OpenMUX-native settings (theme tokens, font settings, scrollback, and similar). Whenever a key is set in `[ghostty]` and is also in the OpenMUX-managed list, the OpenMUX-managed value SHALL win. The system SHALL emit a warning diagnostic naming the conflicting key.

#### Scenario: Theme background wins over pass-through
- **WHEN** the user sets `"background" = "#000000"` under `[ghostty]` and the active theme defines `bg.canvas = "#1a1a1a"`
- **THEN** the engine renders with `#1a1a1a` and a warning diagnostic names `background` as overridden by the active theme

#### Scenario: Non-managed pass-through key is not warned
- **WHEN** the user sets a key under `[ghostty]` that is not in the OpenMUX-managed list
- **THEN** no override diagnostic is emitted and the value is forwarded as-is

### Requirement: User-facing files live under `~/.omux/`
The system SHALL place all user-facing configuration and theme files under `~/.omux/`. The system SHALL place all OpenMUX-managed generated artifacts under `~/.omux/generated/`. Generated artifacts SHALL include a header declaring that they are OpenMUX-managed.

#### Scenario: User edits the right file
- **WHEN** the user opens `~/.omux/config.toml` and `~/.omux/themes/<name>.toml`
- **THEN** these are the canonical edit surfaces, and OpenMUX honors changes to them

#### Scenario: Generated file warns against hand-editing
- **WHEN** the user opens any file under `~/.omux/generated/`
- **THEN** the file begins with a header comment naming the source `~/.omux/config.toml`, the active theme, the OpenMUX version, and a notice that the file is regenerated on every reload
