## MODIFIED Requirements

### Requirement: Keyboard input is normalized before dispatch
The system SHALL classify macOS keyboard and text-input events into OpenMUX-owned shortcuts, terminal-owned input, composition state, or observation metadata before they are used for shell commands, hooks, or bridge-owned adaptation into a hosted libghostty surface. Runtime-backed terminal panes SHALL NOT treat a modifier such as Command as sufficient by itself to claim input for OpenMUX.

#### Scenario: One input model serves multiple consumers
- **WHEN** a key event enters the application
- **THEN** the system converts it into a shared classified representation before terminal or shell behavior is applied

#### Scenario: Unclaimed Command chord remains terminal-owned
- **WHEN** a focused runtime-backed terminal pane receives a Command-modified key chord that is not an explicit OpenMUX shortcut or native menu command
- **THEN** OpenMUX SHALL allow the input to continue through the terminal runtime input path instead of discarding it as a generic shortcut

## ADDED Requirements

### Requirement: OpenMUX shortcuts are allowlisted
The system SHALL intercept only explicit OpenMUX-owned key commands for workspace navigation, sidebar visibility, pane splitting, and other shell-owned behavior.

#### Scenario: Known split shortcut is intercepted
- **WHEN** a focused terminal pane receives `Cmd+D` or `Cmd+Shift+D`
- **THEN** OpenMUX SHALL perform the matching split command and SHALL NOT send that key chord as terminal input

#### Scenario: Unknown Command chord is not intercepted
- **WHEN** a focused terminal pane receives a Command-modified key chord with no OpenMUX command binding
- **THEN** OpenMUX SHALL leave terminal input semantics to the runtime adapter and Ghostty

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
