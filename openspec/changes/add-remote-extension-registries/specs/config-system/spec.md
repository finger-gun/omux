## ADDED Requirements

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
