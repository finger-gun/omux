## ADDED Requirements

### Requirement: Plugin manifests SHALL declare native menu contributions
The system SHALL allow installed plugin manifests to declare optional native menu contributions using local metadata that does not require executing plugin code or contacting a remote registry.

#### Scenario: Installed plugin declares menu item
- **WHEN** an installed plugin manifest declares a valid menu contribution
- **THEN** OpenMUX exposes the contribution as local plugin metadata available to the app shell

#### Scenario: Plugin has no menu metadata
- **WHEN** an installed plugin manifest omits menu contribution metadata
- **THEN** OpenMUX treats the plugin as valid and contributes no native menu items

### Requirement: Plugin menu items SHALL use explicit command targets
Plugin menu contributions SHALL declare explicit command targets that either invoke the contributing plugin command or a supported built-in OpenMUX command identifier.

#### Scenario: Plugin command menu item is selected
- **WHEN** the user selects a plugin-contributed menu item whose target is the plugin command
- **THEN** OpenMUX invokes the installed plugin command with the declared arguments

#### Scenario: Built-in command menu item is selected
- **WHEN** the user selects a plugin-contributed menu item whose target is an allowed built-in OpenMUX command identifier
- **THEN** OpenMUX invokes that command through the typed command/action path rather than through shell text

#### Scenario: Unsupported target is ignored
- **WHEN** a plugin manifest declares a menu item with an unsupported target kind or unsafe command
- **THEN** OpenMUX ignores that menu item and surfaces a diagnostic without invalidating the whole plugin

### Requirement: Plugin menu discovery SHALL be local and deterministic
The app shell SHALL build plugin-contributed menus from installed local plugin metadata only, without running plugin processes during menu construction.

#### Scenario: App builds menus
- **WHEN** OpenMUX constructs or refreshes native menus
- **THEN** plugin menu items are derived from local installed manifests and sorted deterministically by declared location and title

#### Scenario: Plugin is uninstalled
- **WHEN** a plugin with menu contributions is uninstalled
- **THEN** its menu items disappear on the next menu refresh without leaving stale command targets
