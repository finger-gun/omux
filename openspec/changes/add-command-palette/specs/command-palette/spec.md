## ADDED Requirements

### Requirement: Palette SHALL open in workspace mode from Cmd+P
The system SHALL open a native command palette overlay when the user invokes the default `Cmd+P` shortcut, with an empty query and workspace search mode active.

#### Scenario: Cmd+P opens workspace search
- **WHEN** the app is focused and the user presses `Cmd+P`
- **THEN** OpenMUX opens the command palette with an empty search field and workspace results

#### Scenario: Palette focus is restored after dismissal
- **WHEN** the user dismisses the palette opened from a focused terminal pane
- **THEN** OpenMUX restores focus to the previously focused terminal surface without sending palette text to the terminal

### Requirement: Palette SHALL open in command mode from Cmd+Shift+P
The system SHALL open the same command palette overlay when the user invokes the default `Cmd+Shift+P` shortcut, with `>` prefilled as the first query character and command search mode active.

#### Scenario: Cmd+Shift+P opens command search
- **WHEN** the app is focused and the user presses `Cmd+Shift+P`
- **THEN** OpenMUX opens the command palette with `>` in the search field and command results

#### Scenario: Caret follows command prefix
- **WHEN** the palette opens from `Cmd+Shift+P`
- **THEN** the text insertion point is positioned after the prefilled `>` prefix

### Requirement: Palette SHALL switch modes based on leading prefix
The palette SHALL treat a leading `>` query character as command mode and SHALL treat queries without a leading `>` as workspace mode.

#### Scenario: User types command prefix
- **WHEN** the palette is open in workspace mode and the user enters `>` as the first query character
- **THEN** OpenMUX switches the result list to command mode and matches against the query text after the prefix

#### Scenario: User removes command prefix
- **WHEN** the palette is open in command mode and the user removes the leading `>` prefix
- **THEN** OpenMUX switches the result list back to workspace mode

### Requirement: Workspace mode SHALL search switchable workspaces
In workspace mode, the palette SHALL search switchable OpenMUX workspaces and SHALL activate the selected workspace through the shared workspace action model.

#### Scenario: Workspace result is selected
- **WHEN** the user selects a workspace result from the palette
- **THEN** OpenMUX activates that workspace through the shared workspace/session action path

#### Scenario: Workspace mode excludes commands
- **WHEN** the palette query does not start with `>`
- **THEN** OpenMUX shows workspace results rather than shortcut command or `omux` CLI command results

### Requirement: Command mode SHALL search invokable commands
In command mode, the palette SHALL search available shortcut-backed OpenMUX actions and supported `omux` CLI commands using explicit command metadata.

#### Scenario: Shortcut-backed command is selected
- **WHEN** the user selects a shortcut-backed action result from command mode
- **THEN** OpenMUX invokes that action through the action dispatch path

#### Scenario: CLI-backed command is selected
- **WHEN** the user selects a supported `omux` CLI command result from command mode
- **THEN** OpenMUX invokes the corresponding control-plane operation through an explicit supported command contract

### Requirement: Palette results SHALL expose inspectable metadata
Palette results SHALL include a stable identifier, title, category, match text, enabled state, invocation target, and optional subtitle, shortcut label, and disabled reason.

#### Scenario: Result displays shortcut metadata
- **WHEN** a command result has an associated effective shortcut
- **THEN** the palette can display the shortcut label from result metadata without hardcoding it in the UI

#### Scenario: Disabled result is explicit
- **WHEN** a command is known but not invokable in the current context
- **THEN** the palette result marks it disabled and provides an optional disabled reason instead of failing only after selection

### Requirement: Palette search SHALL remain local and lightweight
The initial palette search implementation SHALL use local in-memory workspace and command metadata and SHALL NOT require browser UI, network access, or persistent background indexing.

#### Scenario: Palette opens without background service
- **WHEN** the user opens the palette
- **THEN** OpenMUX presents results using local app state without starting a separate indexing service

#### Scenario: Palette does not use browser chrome
- **WHEN** the palette is displayed
- **THEN** it is rendered as native app chrome rather than a browser or webview command surface
