## MODIFIED Requirements

### Requirement: Keyboard input is normalized before dispatch
The system SHALL normalize macOS keyboard and text-input events into an OpenMUX input model before they are used for interactive terminal dispatch, keybindings, hooks, or session-control behavior.

#### Scenario: One input model serves multiple consumers
- **WHEN** a key or text-input event enters the application
- **THEN** the system converts it into a shared normalized representation before terminal or shell behavior is applied

### Requirement: International keyboard behavior is first-class
The system SHALL support ISO and EU keyboard layouts, including Alt/Option combinations, dead keys, compose-related behavior, and composed text delivery in live interactive panes as a foundation requirement.

#### Scenario: International input is not treated as an edge case
- **WHEN** a user types with an ISO or EU keyboard layout in an interactive pane
- **THEN** the system preserves intended text input and modifier semantics without requiring layout-specific hacks outside the input pipeline

## ADDED Requirements

### Requirement: Terminal editing keys SHALL stay distinct from text insertion
The system SHALL preserve the distinction between text-producing input and terminal-control input such as return, delete, arrows, and paste so live sessions receive the intended behavior.

#### Scenario: Editing keys do not become plain text
- **WHEN** a user presses return, backspace, or an arrow key in a focused terminal pane
- **THEN** the system routes the normalized event as terminal control input rather than inserting literal characters into the pane text model
