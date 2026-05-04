## ADDED Requirements

### Requirement: OpenMUX shortcuts SHALL support scoped structural commands
The input pipeline SHALL explicitly allowlist scoped structural shortcuts for pane tabs, pane splitting/removal, and workspace create/delete actions without broadening interception of unrelated terminal input.

#### Scenario: Pane remove shortcut is intercepted exactly
- **WHEN** a focused terminal pane receives `Cmd+Shift+W`
- **THEN** OpenMUX SHALL route the chord as a pane remove shortcut instead of sending it as terminal input

#### Scenario: Workspace close shortcut is intercepted exactly
- **WHEN** a focused terminal pane receives `Cmd+Shift+N`
- **THEN** OpenMUX SHALL route the chord as a workspace close/delete shortcut instead of sending it as terminal input

#### Scenario: Existing shortcuts remain allowlisted
- **WHEN** a focused terminal pane receives existing OpenMUX shortcuts including `Cmd+T`, `Cmd+W`, `Cmd+D`, `Cmd+Shift+D`, `Cmd+N`, workspace number shortcuts, or sidebar shortcuts
- **THEN** OpenMUX SHALL continue routing those chords to shell actions

#### Scenario: Unassigned pane-add alias remains terminal-owned
- **WHEN** a focused terminal pane receives `Cmd+Shift+T`
- **THEN** OpenMUX SHALL leave the input to terminal runtime semantics

#### Scenario: Option and unknown chords remain terminal-owned
- **WHEN** a focused terminal pane receives an Option-modified chord or an unrecognized Command chord
- **THEN** OpenMUX SHALL leave the input to terminal runtime semantics
