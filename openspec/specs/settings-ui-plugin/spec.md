# settings-ui-plugin Specification

## Purpose
TBD - created by archiving change add-plugin-settings-ui. Update Purpose after archive.
## Requirements
### Requirement: Settings UI plugin SHALL open a graphical config pane
The `settings-ui` registry plugin SHALL open an extension pane that renders supported OpenMUX configuration values as a local graphical form.

#### Scenario: User opens settings UI
- **WHEN** the user runs `omux settings-ui`
- **THEN** OpenMUX opens an extension pane titled for settings and populated from the current effective configuration

#### Scenario: Config cannot be loaded
- **WHEN** the plugin cannot load configuration data
- **THEN** the extension pane displays an explicit error state with the diagnostic text

### Requirement: Settings UI plugin SHALL save through OpenMUX config APIs
The `settings-ui` plugin SHALL save changes by calling OpenMUX-owned config apply/reload commands, not by directly rewriting `~/.omux/config.toml` from pane JavaScript.

#### Scenario: User saves valid settings
- **WHEN** the user edits supported settings and activates Save
- **THEN** the plugin submits changes through the extension-pane action bridge and `omux config apply`
- **AND** OpenMUX validates, writes, reloads, and reports success in the pane

#### Scenario: User saves invalid settings
- **WHEN** the user submits values that fail validation
- **THEN** the pane remains open and displays the returned config diagnostics without applying invalid runtime state

### Requirement: Settings UI plugin SHALL preserve TOML as the canonical surface
The settings UI SHALL make clear that `~/.omux/config.toml` remains the canonical config file and SHALL provide a way to open or reload configuration through OpenMUX commands.

#### Scenario: User wants direct editing
- **WHEN** the settings pane is displayed
- **THEN** it includes an affordance or menu contribution for opening the config file directly

#### Scenario: User reloads config
- **WHEN** the user invokes the plugin-provided reload command
- **THEN** OpenMUX runs the standard config reload behavior and reports diagnostics consistently with `omux config reload`

