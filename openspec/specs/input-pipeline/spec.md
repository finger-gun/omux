# input-pipeline Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.
## Requirements
### Requirement: Keyboard input is normalized before dispatch
The system SHALL classify macOS keyboard and text-input events into OpenMUX-owned shortcuts, terminal-owned input, composition state, or observation metadata before they are used for shell commands, hooks, or bridge-owned adaptation into a hosted libghostty surface. Runtime-backed terminal panes SHALL NOT treat a modifier such as Command as sufficient by itself to claim input for OpenMUX.

#### Scenario: One input model serves multiple consumers
- **WHEN** a key event enters the application
- **THEN** the system converts it into a shared classified representation before terminal or shell behavior is applied

#### Scenario: Unclaimed Command chord remains terminal-owned
- **WHEN** a focused runtime-backed terminal pane receives a Command-modified key chord that is not an explicit OpenMUX shortcut or native menu command
- **THEN** OpenMUX SHALL allow the input to continue through the terminal runtime input path instead of discarding it as a generic shortcut

### Requirement: International keyboard behavior is first-class
The system SHALL support ISO and EU keyboard layouts, including Alt/Option combinations, dead keys, and compose-related behavior, as a foundation requirement for both shell shortcuts and hosted libghostty pane input.

#### Scenario: International input is not treated as an edge case
- **WHEN** a user types with an ISO or EU keyboard layout
- **THEN** the system preserves intended text input and modifier semantics without requiring layout-specific hacks outside the input pipeline

### Requirement: Left and right modifiers remain distinguishable where required
The system SHALL preserve left/right modifier identity where needed to support correct terminal and shortcut behavior, including right-Option-sensitive flows that must survive delivery into a hosted libghostty surface.

#### Scenario: Right-Option behavior remains addressable
- **WHEN** right-Option behavior differs from left-Option behavior for a layout or workflow
- **THEN** the input model retains enough modifier information to support the distinction through terminal dispatch

### Requirement: Terminal editing keys SHALL stay distinct from text insertion
The system SHALL preserve the distinction between text-producing input and terminal-control input such as return, delete, arrows, and paste so live sessions receive the intended behavior.

#### Scenario: Editing keys do not become plain text
- **WHEN** a user presses return, backspace, or an arrow key in a focused terminal pane
- **THEN** the system routes the normalized event as terminal control input rather than inserting literal characters into the pane text model

### Requirement: Shell shortcuts SHALL remain distinct from terminal text input
The system SHALL route shell-owned shortcut commands for workspace navigation, sidebar visibility, and split actions separately from terminal text input so focused panes do not receive those commands as plain text.

#### Scenario: Split shortcut does not insert terminal text
- **WHEN** a terminal pane is focused and the user presses `Cmd+D` or `Cmd+Shift+D`
- **THEN** the shell invokes the matching split action instead of inserting `d` or `D` into the terminal session

#### Scenario: Workspace shortcut does not insert terminal digits
- **WHEN** a terminal pane is focused and the user presses `Cmd+1` through `Cmd+9`, `Cmd+0`, or `Cmd+B`
- **THEN** the shell invokes the matching workspace navigation or sidebar command instead of inserting terminal text

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

### Requirement: OpenMUX does not synthesize terminal editing semantics
The system SHALL NOT hardcode shell-editing substitutions for terminal-owned key chords when the original key event can be represented to Ghostty.

#### Scenario: Option Backspace reaches terminal semantics
- **WHEN** a focused runtime-backed terminal pane receives `Option+Backspace`
- **THEN** OpenMUX SHALL NOT translate it to an OpenMUX-owned `Ctrl+W` or other shell-editing substitute
- **AND** the original key and modifier facts SHALL be available to Ghostty runtime input handling

#### Scenario: Command Backspace reaches terminal semantics
- **WHEN** a focused runtime-backed terminal pane receives `Cmd+Backspace` and no OpenMUX shortcut claims it
- **THEN** OpenMUX SHALL NOT translate it to an OpenMUX-owned line-delete substitute
- **AND** the original key and modifier facts SHALL be available to Ghostty runtime input handling

### Requirement: OpenMUX navigation shortcuts SHALL be explicitly allowlisted
The input pipeline SHALL classify only the documented pane-local tab and pane navigation key chords as OpenMUX shortcuts while preserving terminal ownership of unclaimed Control, Command, Option/Alt, dead-key, compose, and IME input.

#### Scenario: Pane-local tab shortcuts are intercepted
- **WHEN** a focused runtime-backed terminal pane receives `Cmd+T`, `Cmd+W`, or `Ctrl+Tab`
- **THEN** OpenMUX classifies the event as a shortcut and the terminal session does not receive the key chord as text input

#### Scenario: Pane cycle shortcut is intercepted
- **WHEN** a focused runtime-backed terminal pane receives `Ctrl+Shift+Tab`
- **THEN** OpenMUX classifies the event as a shortcut and the terminal session does not receive the key chord as text input

#### Scenario: Other Control chords remain terminal input
- **WHEN** a focused runtime-backed terminal pane receives a Control-modified key chord that is not an explicit OpenMUX shortcut
- **THEN** OpenMUX leaves the event terminal-owned with original key and modifier facts preserved

#### Scenario: Option and composition input remain terminal input
- **WHEN** a focused runtime-backed terminal pane receives Option/Alt text input, right-Option-sensitive input, dead-key input, compose input, or IME composition input that is not an explicit OpenMUX shortcut
- **THEN** OpenMUX preserves the intended terminal or composition route instead of treating it as pane navigation

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

