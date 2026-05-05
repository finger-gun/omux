## ADDED Requirements

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
