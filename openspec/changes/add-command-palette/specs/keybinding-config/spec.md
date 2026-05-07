## ADDED Requirements

### Requirement: Built-in keybindings SHALL include command palette entry points
The system SHALL include built-in default keybindings for opening the command palette in workspace mode and command mode, and those bindings SHALL remain configurable defaults rather than hardcoded reserved shortcuts.

#### Scenario: Cmd+P default opens workspace palette
- **WHEN** OpenMUX starts without a user override for `Cmd+P`
- **THEN** the effective keybinding registry maps `Cmd+P` to the action that opens the command palette with an empty query

#### Scenario: Cmd+Shift+P default opens command palette
- **WHEN** OpenMUX starts without a user override for `Cmd+Shift+P`
- **THEN** the effective keybinding registry maps `Cmd+Shift+P` to the action that opens the command palette with `>` prefilled

#### Scenario: User can override palette bindings
- **WHEN** the user maps either palette shortcut to another supported action or to `"none"`
- **THEN** the effective keybinding registry applies the user override using the existing deterministic keybinding layering rules

#### Scenario: Unbound palette shortcut is not claimed
- **WHEN** the user maps a default palette shortcut to `"none"`
- **THEN** OpenMUX does not claim that chord for the palette and allows normal terminal input routing to handle it when representable

### Requirement: Palette keybindings SHALL avoid Option-modified shortcuts
The default command palette keybindings SHALL use Command-only or Command-plus-Shift chords and SHALL NOT require Option-modified chords.

#### Scenario: International text input remains protected
- **WHEN** the command palette keybindings are loaded
- **THEN** no default palette binding claims an Option-modified chord that could conflict with right-Option, dead-key, or layout-specific text input
