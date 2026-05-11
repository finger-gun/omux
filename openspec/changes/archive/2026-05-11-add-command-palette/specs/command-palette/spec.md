## ADDED Requirements

### Requirement: Palette SHALL open in workspace mode from Cmd+P
The system SHALL open a native command palette overlay when the user invokes the default `Cmd+P` shortcut, with an empty query, workspace search mode active, and currently open workspaces listed immediately.

#### Scenario: Cmd+P opens workspace search
- **WHEN** the app is focused and the user presses `Cmd+P`
- **THEN** OpenMUX opens the command palette with an empty search field and all open workspaces listed in workspace mode

#### Scenario: Palette focus is restored after dismissal
- **WHEN** the user dismisses the palette opened from a focused terminal pane
- **THEN** OpenMUX restores focus to the previously focused terminal surface without sending palette text to the terminal

### Requirement: Palette SHALL open in command mode from Cmd+Shift+P
The system SHALL open the same command palette overlay when the user invokes the default `Cmd+Shift+P` shortcut, with `>` prefilled as the first query character, command search mode active, and command results listed immediately.

#### Scenario: Cmd+Shift+P opens command search
- **WHEN** the app is focused and the user presses `Cmd+Shift+P`
- **THEN** OpenMUX opens the command palette with `>` in the search field and safe discoverable command results

#### Scenario: Caret follows command prefix
- **WHEN** the palette opens from `Cmd+Shift+P`
- **THEN** the text insertion point is positioned after the prefilled `>` prefix

### Requirement: Palette SHALL switch modes based on leading prefix
The palette SHALL treat `>` as command mode only when it is the first query character, SHALL treat queries without a first-character `>` as workspace mode, and SHALL NOT define an escaping syntax for literal leading-`>` workspace searches in v1.

#### Scenario: User types command prefix
- **WHEN** the palette is open in workspace mode and the user enters `>` as the first query character
- **THEN** OpenMUX switches the result list to command mode and matches against the query text after the prefix

#### Scenario: Whitespace before prefix remains workspace mode
- **WHEN** the palette query begins with whitespace followed by `>`
- **THEN** OpenMUX treats the query as workspace mode text rather than command mode

#### Scenario: User removes command prefix
- **WHEN** the palette is open in command mode and the user removes the leading `>` prefix
- **THEN** OpenMUX switches the result list back to workspace mode

### Requirement: Workspace mode SHALL search switchable workspaces
In workspace mode, the palette SHALL search currently open switchable OpenMUX workspaces by display name and path, SHALL rank display-name matches above path-only matches, and SHALL activate non-current selected workspaces through the shared workspace action model.

#### Scenario: Workspace result is selected
- **WHEN** the user selects a workspace result from the palette
- **THEN** OpenMUX activates that workspace through the shared workspace/session action path

#### Scenario: Empty workspace query lists open workspaces
- **WHEN** the palette opens in workspace mode with an empty query
- **THEN** OpenMUX lists currently open workspaces using visible workspace order as the stable tiebreaker

#### Scenario: Active workspace selection is inert
- **WHEN** the user selects the currently active workspace result
- **THEN** OpenMUX dismisses the palette, restores focus, and does not emit a workspace switch event

#### Scenario: Workspace mode excludes commands
- **WHEN** the palette query does not start with `>`
- **THEN** OpenMUX shows workspace results rather than shortcut command or `omux` CLI command results

### Requirement: Command mode SHALL search invokable commands
In command mode, the palette SHALL search safe discoverable OpenMUX actions and supported safe-default `omux` CLI commands using explicit command metadata. Built-in command metadata SHALL be loadable from bundled JSON command descriptor files that define presentation fields and a typed `command.kind` plus `command.target` identifier. The system SHALL hide argument-requiring actions or CLI commands unless they have safe focused/default targets.

#### Scenario: Safe action command is selected
- **WHEN** the user selects a safe OpenMUX action result from command mode
- **THEN** OpenMUX invokes that action through the action dispatch path

#### Scenario: CLI-backed command is selected
- **WHEN** the user selects a supported `omux` CLI command result from command mode
- **THEN** OpenMUX invokes the corresponding control-plane operation through an explicit supported command contract

#### Scenario: Argument-requiring command is hidden
- **WHEN** an action or CLI command requires freeform text, a file path, or an explicit selector that the palette cannot safely default
- **THEN** OpenMUX does not include that command in command-mode results

#### Scenario: Empty command query lists commands
- **WHEN** the palette opens in command mode with only the `>` prefix
- **THEN** OpenMUX lists safe discoverable command results immediately

#### Scenario: Descriptor-backed command is discovered
- **WHEN** command mode loads bundled command descriptor files
- **THEN** OpenMUX turns valid descriptors into command results using descriptor titles, categories, match text, aliases, argument requirements, enabled state, and typed command targets

#### Scenario: Descriptor does not define shell execution
- **WHEN** a descriptor defines `command.kind` and `command.target`
- **THEN** OpenMUX treats the target as an identifier resolved by a typed registry rather than as bash, shell text, or an executable command string

### Requirement: Palette results SHALL expose inspectable metadata
Palette results SHALL include a stable identifier, title, category, match text, enabled state, invocation target derived from a typed command descriptor or workspace target, and optional subtitle, shortcut label, aliases, and disabled reason.

#### Scenario: Result displays shortcut metadata
- **WHEN** a command result has an associated effective shortcut
- **THEN** the palette can display the shortcut label from result metadata without hardcoding it in the UI

#### Scenario: Disabled result is explicit
- **WHEN** a command is known but not invokable in the current context
- **THEN** the palette result marks it disabled and provides an optional disabled reason instead of failing only after selection

#### Scenario: Disabled result appears when matched
- **WHEN** a disabled command matches the user's command-mode query
- **THEN** OpenMUX may show the command with a disabled reason and SHALL NOT invoke it while disabled

### Requirement: Palette interactions SHALL be deterministic and native
The palette SHALL use deterministic ranked matching with stable tiebreakers, SHALL reset the query from the invoking shortcut each time it opens or is reopened, SHALL close after successful invocation, and SHALL use native accessible controls for result rows.

#### Scenario: Reopening resets to shortcut mode
- **WHEN** the palette is already open and the user invokes `Cmd+P` or `Cmd+Shift+P`
- **THEN** OpenMUX keeps the palette open and resets the query to the mode implied by the invoked shortcut

#### Scenario: Return invokes selected enabled result
- **WHEN** the palette has a selected enabled result and the user presses Return
- **THEN** OpenMUX invokes that result and closes the palette after successful invocation

#### Scenario: Return with no enabled result is inert
- **WHEN** the palette has no enabled selected result and the user presses Return
- **THEN** OpenMUX keeps the palette open and provides feedback without invoking a result

#### Scenario: Escape respects composition
- **WHEN** the palette search field has active marked text or IME composition and the user presses Escape
- **THEN** OpenMUX cancels the composition before a subsequent Escape closes the palette

#### Scenario: Result rows remain accessible controls
- **WHEN** the palette renders result rows
- **THEN** those rows use native accessible control or list semantics rather than decorative drawing without roles or labels

### Requirement: Palette search SHALL remain local and lightweight
The initial palette search implementation SHALL use local in-memory workspace and command metadata and SHALL NOT require browser UI, network access, or persistent background indexing.

#### Scenario: Palette opens without background service
- **WHEN** the user opens the palette
- **THEN** OpenMUX presents results using local app state without starting a separate indexing service

#### Scenario: Palette does not use browser chrome
- **WHEN** the palette is displayed
- **THEN** it is rendered as native app chrome rather than a browser or webview command surface
