## ADDED Requirements

### Requirement: Keybindings SHALL be configurable with single chords
The system SHALL expose a `[keys]` TOML table where each entry maps one normalized key chord to one supported OpenMUX action identifier or to `"none"`.

#### Scenario: User binds a shell action
- **WHEN** the config contains `[keys] "cmd+shift+w" = "pane.remove"`
- **THEN** the effective keybinding registry maps `Cmd+Shift+W` to the pane remove action

#### Scenario: User unbinds a chord
- **WHEN** the config contains `[keys] "cmd+shift+backspace" = "none"`
- **THEN** the effective keybinding registry does not claim `Cmd+Shift+Backspace` for any OpenMUX action

### Requirement: Built-in keybindings SHALL remain available without config
The system SHALL provide documented built-in keybindings for OpenMUX shell actions when the user config is absent or omits `[keys]`.

#### Scenario: No key table is configured
- **WHEN** OpenMUX starts without a `[keys]` table
- **THEN** the effective keybinding registry contains the documented built-in shortcuts

#### Scenario: Partial key table is configured
- **WHEN** the user configures only one keybinding override
- **THEN** every unspecified action keeps its built-in keybinding

### Requirement: User keybindings SHALL override defaults deterministically
The system SHALL layer user `[keys]` entries over built-in defaults and SHALL resolve each chord to at most one effective action.

#### Scenario: User rebinds a default chord
- **WHEN** a user maps a default chord to a different supported action
- **THEN** the effective registry uses the user-specified action for that chord

#### Scenario: User unbinds a default chord
- **WHEN** a user maps a default chord to `"none"`
- **THEN** the effective registry removes the default action from that chord

### Requirement: Keybinding validation SHALL protect terminal input
The system SHALL reject malformed chords, unknown actions, duplicate effective chords, and unsafe modifier combinations with structured diagnostics.

#### Scenario: Unknown action is rejected
- **WHEN** the config maps a chord to an unsupported action identifier
- **THEN** the loader emits a hard-error diagnostic naming the unsupported action

#### Scenario: Malformed chord is rejected
- **WHEN** the config contains a chord string that cannot be parsed
- **THEN** the loader emits a hard-error diagnostic naming the malformed chord

#### Scenario: Option chord is rejected
- **WHEN** the config maps an Option-modified chord
- **THEN** the loader emits a diagnostic explaining that Option/right-Option bindings are not supported because they conflict with international text input

### Requirement: Keybinding action identifiers SHALL be stable and documented
The system SHALL document supported action identifiers for v1 keybindings and SHALL NOT treat arbitrary strings as executable commands.

#### Scenario: Supported actions are used
- **WHEN** a user binds a documented action identifier such as `pane-tab.create`, `pane.remove`, or `workspace.close`
- **THEN** OpenMUX accepts the binding and routes matching chords to that action

#### Scenario: Arbitrary command is not executed
- **WHEN** a user maps a chord to a shell command string
- **THEN** OpenMUX rejects the value as an unknown action instead of executing it
