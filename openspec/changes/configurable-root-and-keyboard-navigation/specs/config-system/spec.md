## ADDED Requirements

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
