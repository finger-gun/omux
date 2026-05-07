## MODIFIED Requirements

### Requirement: Theme changes apply live
The system SHALL recompile and re-apply the theme without restarting terminal sessions when the active theme is changed via configuration edit, when the active theme file is edited, when an explicit reload is requested, **or when the user selects a theme from the command palette theme switcher**.

#### Scenario: Switch theme by editing config
- **WHEN** the user edits `~/.omux/config.toml` to change `[theme] name` from `monokai-soda` to `nord`
- **THEN** the chrome and the engine both reflect `nord` without any terminal session being killed

#### Scenario: Edit active theme file
- **WHEN** the user edits a token value in `~/.omux/themes/<active>.toml`
- **THEN** the chrome and the engine reflect the new token value without any terminal session being killed

#### Scenario: Switch theme from command palette
- **WHEN** the user selects a theme from the command palette theme switcher and confirms
- **THEN** `~/.omux/config.toml` is updated with the new theme name, the chrome and engine both reflect the new theme without any terminal session being killed, and the configuration coordinator fires `onThemeChange`

#### Scenario: Preview theme from command palette
- **WHEN** the user highlights a theme in the command palette theme switcher without confirming
- **THEN** the chrome reflects the previewed theme immediately; `~/.omux/config.toml` is NOT modified

#### Scenario: Cancel theme preview from command palette
- **WHEN** the user presses ESC after previewing one or more themes in the command palette
- **THEN** the chrome reverts to the theme that was active before the sub-palette was opened; `~/.omux/config.toml` is NOT modified

## ADDED Requirements

### Requirement: Configuration coordinator exposes programmatic theme selection
The `OpenMUXConfigurationCoordinator` SHALL expose a `setTheme(identifier:)` method that persists the given theme identifier to `~/.omux/config.toml` and triggers the `onThemeChange` callback with the newly loaded theme.

#### Scenario: setTheme persists and notifies
- **WHEN** `setTheme(identifier: "nord")` is called on the coordinator
- **THEN** `~/.omux/config.toml` is updated to set `[theme] name = "nord"` and `onThemeChange` fires with the `nord` theme

#### Scenario: setTheme with unknown identifier
- **WHEN** `setTheme(identifier: "nonexistent-theme")` is called
- **THEN** the method returns an error and `~/.omux/config.toml` is NOT modified
