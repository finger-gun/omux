## ADDED Requirements

### Requirement: Configuration SHALL support workspace shell history isolation
The configuration system SHALL decode, validate, document, and expose a `[workspace] isolate_shell_history` boolean setting. The setting SHALL default to `true`. When set to `false`, OpenMUX SHALL leave shell history file selection to the user's shell configuration while still exposing OpenMUX workspace context environment variables.

#### Scenario: Default isolates shell history
- **WHEN** the user config omits `[workspace] isolate_shell_history`
- **THEN** the effective configuration enables workspace shell history isolation

#### Scenario: User disables shell history isolation
- **WHEN** the user config sets `[workspace] isolate_shell_history = false`
- **THEN** OpenMUX does not set `HISTFILE` for newly launched terminal sessions

#### Scenario: Invalid shell history isolation setting is diagnosed
- **WHEN** the user config sets `[workspace] isolate_shell_history` to a non-boolean value
- **THEN** the loader emits a hard-error diagnostic with file and line information when available

#### Scenario: Config init includes shell history isolation
- **WHEN** the user runs `omux config init`
- **THEN** the generated config includes the documented default `isolate_shell_history = true` under `[workspace]`
