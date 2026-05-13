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

### Requirement: Workspace default root SHALL be configurable
The system SHALL accept a `[workspace] default_root_path` string setting in `~/.omux/config.toml` that defines the default root path for workspace-open flows that do not provide an explicit path. When unset, the built-in default SHALL be the current user's home directory.

#### Scenario: Configured default root loads
- **WHEN** the user config contains `schema = 1` and `[workspace] default_root_path = "~/projects"`
- **THEN** the effective configuration exposes the default workspace root as the expanded absolute path for `~/projects`

#### Scenario: Unset default root uses home
- **WHEN** the user config omits `[workspace] default_root_path`
- **THEN** the effective configuration uses the current user's home directory as the default workspace root

#### Scenario: Invalid default root is diagnosed
- **WHEN** the user config sets `[workspace] default_root_path` to a non-string value or an unusable path
- **THEN** the loader emits a hard-error diagnostic with file and line information when available

#### Scenario: Unknown workspace key is rejected
- **WHEN** the user config contains an unsupported key under `[workspace]`
- **THEN** the loader emits a hard-error diagnostic naming the unknown `[workspace]` key

### Requirement: Configuration SHALL include user keybindings
The configuration system SHALL decode, validate, and expose a `[keys]` table as part of the OpenMUX-owned user-facing configuration file.

#### Scenario: Keys table loads
- **WHEN** `~/.omux/config.toml` contains a valid `[keys]` table
- **THEN** the loader exposes the configured keybinding entries in the loaded configuration

#### Scenario: Unknown keys table values produce diagnostics
- **WHEN** `~/.omux/config.toml` contains invalid keybinding entries
- **THEN** the loader emits structured diagnostics with file path and line information when available

### Requirement: Config init SHALL write all default settings
The `omux config init` command SHALL generate a complete default config file that includes all current OpenMUX-owned default settings and default keybindings.

#### Scenario: New config includes defaults
- **WHEN** the user runs `omux config init`
- **THEN** the generated `~/.omux/config.toml` includes explicit default values for schema, theme, terminal settings, workspace settings, and keybindings

#### Scenario: New config includes keybindings
- **WHEN** the user opens a file generated by `omux config init`
- **THEN** the file contains a `[keys]` table listing every documented default keybinding

#### Scenario: Generated config is immediately valid
- **WHEN** OpenMUX loads a file generated by `omux config init`
- **THEN** the loader accepts it without hard-error diagnostics

### Requirement: Config rewrites SHALL preserve keybindings
The system SHALL preserve `[keys]` entries when config-changing commands rewrite `~/.omux/config.toml`.

#### Scenario: Theme command preserves keybindings
- **WHEN** the user has configured `[keys]` and runs an `omux theme` command that rewrites the config
- **THEN** the rewritten config preserves the user's keybinding entries

### Requirement: Configuration SHALL include persisted scrollback settings
The system SHALL decode, validate, document, and expose OpenMUX-owned persisted scrollback settings from `~/.omux/config.toml`. Persisted scrollback SHALL be enabled by default, SHALL default to 4,000 retained lines, and SHALL include a protective byte limit. Invalid persisted scrollback settings SHALL produce structured configuration diagnostics.

#### Scenario: Defaults enable persisted scrollback
- **WHEN** the user config omits persisted scrollback settings
- **THEN** the effective configuration enables persisted scrollback with a 4,000-line retention limit and the built-in byte cap

#### Scenario: User disables persisted scrollback
- **WHEN** the user config sets persisted scrollback to disabled
- **THEN** OpenMUX does not persist new scrollback payloads and does not visually replay previous scrollback for restored panes

#### Scenario: User configures retained lines
- **WHEN** the user config sets a valid persisted scrollback line limit
- **THEN** OpenMUX uses that line limit when bounding persisted scrollback

#### Scenario: Invalid persisted scrollback setting is diagnosed
- **WHEN** the user config sets persisted scrollback values to invalid types or invalid ranges
- **THEN** the loader emits structured diagnostics with file path and line information when available

### Requirement: Configuration SHALL support optional plugin enablement
The configuration system SHALL decode and validate plugin enablement settings under an OpenMUX-owned plugin configuration table.

#### Scenario: Plugin enablement loads
- **WHEN** `~/.omux/config.toml` contains a valid Markdown preview plugin enablement setting
- **THEN** the effective configuration exposes whether the Markdown preview plugin is enabled

#### Scenario: Invalid plugin key is diagnosed
- **WHEN** the user config contains an unsupported plugin setting or invalid plugin value
- **THEN** the loader emits a structured diagnostic naming the plugin configuration problem

### Requirement: Config init SHALL include documented plugin defaults
The `omux config init` command SHALL include documented default plugin settings for bundled optional plugins.

#### Scenario: Generated config includes Markdown preview settings
- **WHEN** the user runs `omux config init`
- **THEN** the generated config includes the Markdown preview plugin's documented default enablement and relevant settings

### Requirement: Plugin configuration reload SHALL preserve running terminals
Plugin configuration changes SHALL be applied through the same live configuration reload path as other OpenMUX-owned settings without restarting terminal sessions.

#### Scenario: Disabling plugin leaves terminal sessions alive
- **WHEN** the user disables the Markdown preview plugin and reloads configuration
- **THEN** existing terminal sessions remain alive and Markdown preview panes show disabled-plugin state when applicable

### Requirement: Configuration SHALL support extension registry URLs
The configuration system SHALL decode and validate hook and plugin registry URL lists under an OpenMUX-owned registry configuration table.

#### Scenario: Registry URLs load
- **WHEN** `~/.omux/config.toml` contains valid hook and plugin registry URL lists
- **THEN** the effective configuration exposes those URLs for `omux hooks` and `omux plugins` registry commands

#### Scenario: Invalid registry URL is diagnosed
- **WHEN** the user config contains a non-string registry entry or unsupported registry URL
- **THEN** the loader emits a structured diagnostic naming the invalid registry setting

#### Scenario: Missing registry config uses defaults
- **WHEN** the user config omits registry settings
- **THEN** OpenMUX uses the documented official hook and plugin registries as defaults

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

