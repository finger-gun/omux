## MODIFIED Requirements

### Requirement: OpenMUX shortcuts are allowlisted
The system SHALL intercept only explicit OpenMUX-owned key commands present in the effective keybinding registry for workspace navigation, sidebar visibility, pane splitting, pane tabs, pane removal, workspace close, and other shell-owned behavior.

#### Scenario: Known split shortcut is intercepted
- **WHEN** a focused terminal pane receives `Cmd+D` or `Cmd+Shift+D` and those chords are bound to split actions
- **THEN** OpenMUX SHALL perform the matching split command and SHALL NOT send that key chord as terminal input

#### Scenario: Unknown Command chord is not intercepted
- **WHEN** a focused terminal pane receives a Command-modified key chord with no OpenMUX command binding
- **THEN** OpenMUX SHALL leave terminal input semantics to the runtime adapter and Ghostty

#### Scenario: Unbound default chord is not intercepted
- **WHEN** a focused terminal pane receives a chord that was a built-in default but the user configured that chord as `"none"`
- **THEN** OpenMUX SHALL leave terminal input semantics to the runtime adapter and Ghostty

#### Scenario: Rebound chord is intercepted for configured action
- **WHEN** a focused terminal pane receives a chord bound by `[keys]` to a supported OpenMUX action
- **THEN** OpenMUX SHALL route that chord to the configured shell action

### Requirement: Shell shortcuts SHALL preserve international keyboard correctness
The system SHALL apply shell shortcuts from the effective keybinding registry without breaking ISO/EU keyboard behavior, Option-modified text input, right-Option-sensitive terminal input flows, dead keys, compose input, or IME composition.

#### Scenario: Option-modified text input remains terminal input
- **WHEN** a user types text in a focused terminal pane using Option-based combinations
- **THEN** the system preserves the intended text-input behavior for that layout instead of misrouting it to shell navigation

#### Scenario: Command-based shortcuts stay explicit across layouts
- **WHEN** a user with an ISO or EU keyboard layout invokes a configured `Cmd`-based shell shortcut
- **THEN** the shell triggers the intended shortcut behavior without requiring layout-specific hacks outside the input pipeline

#### Scenario: Composition input is not claimed
- **WHEN** a key event is part of dead-key, compose, or IME composition
- **THEN** OpenMUX SHALL NOT claim it as a keybinding even if the final produced text resembles a configured chord
