## ADDED Requirements

### Requirement: Native menus SHALL include plugin-contributed items
The native macOS shell SHALL include valid plugin-contributed menu items in deterministic locations while preserving existing OpenMUX-owned menu organization and keybinding behavior.

#### Scenario: Plugin contributes Configuration menu items
- **WHEN** an installed plugin declares valid Configuration menu contributions
- **THEN** the app shell displays those items in the Configuration menu or equivalent config-focused menu section

#### Scenario: Plugin menu item is invoked
- **WHEN** the user selects a plugin-contributed native menu item
- **THEN** OpenMUX invokes the declared typed target without routing through terminal input

#### Scenario: Menus refresh after plugin changes
- **WHEN** plugin installation, uninstall, or config reload changes available plugin contributions
- **THEN** the native menus refresh without restarting terminal sessions

### Requirement: Plugin menu items SHALL preserve terminal focus behavior
Invoking plugin-contributed menu items SHALL NOT send menu command text to the focused terminal or disturb terminal keyboard semantics beyond normal focus changes for opened panes.

#### Scenario: Menu item opens settings pane
- **WHEN** a terminal pane is focused and the user selects a plugin menu item that opens a settings pane
- **THEN** no command text is typed into the terminal and the new pane follows normal extension-pane focus behavior

#### Scenario: Menu item reloads config
- **WHEN** a terminal pane is focused and the user selects a plugin menu item that reloads config
- **THEN** the terminal session remains alive and its input encoding behavior is unchanged
