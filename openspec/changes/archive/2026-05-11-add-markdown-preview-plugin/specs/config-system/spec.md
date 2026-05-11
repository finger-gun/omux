## ADDED Requirements

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
