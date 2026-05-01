## ADDED Requirements

### Requirement: Shell shortcuts SHALL remain distinct from terminal text input
The system SHALL route shell-owned shortcut commands for workspace navigation, sidebar visibility, and split actions separately from terminal text input so focused panes do not receive those commands as plain text.

#### Scenario: Split shortcut does not insert terminal text
- **WHEN** a terminal pane is focused and the user presses `Cmd+D` or `Cmd+Shift+D`
- **THEN** the shell invokes the matching split action instead of inserting `d` or `D` into the terminal session

#### Scenario: Workspace shortcut does not insert terminal digits
- **WHEN** a terminal pane is focused and the user presses `Cmd+1` through `Cmd+9`, `Cmd+0`, or `Cmd+B`
- **THEN** the shell invokes the matching workspace navigation or sidebar command instead of inserting terminal text

### Requirement: Shell shortcuts SHALL preserve international keyboard correctness
The system SHALL add shell shortcuts for split and workspace navigation without breaking ISO/EU keyboard behavior, Option-modified text input, or right-Option-sensitive terminal input flows.

#### Scenario: Option-modified text input remains terminal input
- **WHEN** a user types text in a focused terminal pane using Option-based combinations that are not bound to shell commands
- **THEN** the system preserves the intended text-input behavior for that layout instead of misrouting it to shell navigation

#### Scenario: Command-based shortcuts stay explicit across layouts
- **WHEN** a user with an ISO or EU keyboard layout invokes the documented `Cmd`-based shell shortcuts
- **THEN** the shell triggers the intended shortcut behavior without requiring layout-specific hacks outside the input pipeline
