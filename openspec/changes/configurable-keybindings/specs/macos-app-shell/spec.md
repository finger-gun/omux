## ADDED Requirements

### Requirement: Native menus SHALL reflect effective keybindings
The native macOS shell SHALL derive representable menu key equivalents from the effective OpenMUX keybinding registry.

#### Scenario: Default menu shortcuts are shown
- **WHEN** OpenMUX starts without user keybinding overrides
- **THEN** native menu items show the documented default shortcuts

#### Scenario: Rebound menu shortcut is shown
- **WHEN** a user configures a supported representable chord for an action with a native menu item
- **THEN** that menu item shows the configured chord

#### Scenario: Unbound menu shortcut is cleared
- **WHEN** a user configures an action's default chord as `"none"` and no replacement chord is configured
- **THEN** the corresponding menu item does not show the unbound shortcut

### Requirement: Menu and terminal interception SHALL stay coherent
The native macOS shell SHALL keep menu key equivalents and terminal-pane shortcut classification synchronized with the same effective keybinding registry.

#### Scenario: Menu shortcut triggers same action as terminal shortcut
- **WHEN** a chord is displayed on a native menu item and the focused pane receives the same chord
- **THEN** both paths resolve to the same OpenMUX shell action

#### Scenario: Keybinding reload updates menus
- **WHEN** configuration reload changes effective keybindings
- **THEN** native menu key equivalents update without restarting existing terminal sessions
