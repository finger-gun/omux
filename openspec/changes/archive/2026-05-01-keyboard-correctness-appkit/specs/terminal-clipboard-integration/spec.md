## ADDED Requirements

### Requirement: Runtime terminal commands support clipboard actions
Runtime-backed terminal panes SHALL support Copy, Paste, and Select All through terminal runtime commands when the terminal pane is focused.

#### Scenario: Paste command reaches the terminal runtime
- **WHEN** a runtime-backed terminal pane is focused and the user invokes Paste
- **THEN** OpenMUX SHALL route the command to the runtime terminal paste action rather than injecting text through a hidden overlay

#### Scenario: Copy command reaches the terminal runtime
- **WHEN** a runtime-backed terminal pane is focused and the user invokes Copy
- **THEN** OpenMUX SHALL route the command to the runtime terminal copy action

#### Scenario: Select All command reaches the terminal runtime
- **WHEN** a runtime-backed terminal pane is focused and the user invokes Select All
- **THEN** OpenMUX SHALL route the command to the runtime terminal select-all action

### Requirement: Standard macOS clipboard is integrated
Runtime-backed terminal panes SHALL support standard macOS clipboard read and write through OpenMUX-owned host clipboard callbacks.

#### Scenario: Runtime requests clipboard read
- **WHEN** the terminal runtime requests standard clipboard contents
- **THEN** OpenMUX SHALL read text from the standard macOS pasteboard and complete the runtime clipboard request

#### Scenario: Runtime requests clipboard write
- **WHEN** the terminal runtime requests writing text to the standard clipboard
- **THEN** OpenMUX SHALL write the requested text to the standard macOS pasteboard

### Requirement: Clipboard requests use explicit policy
OpenMUX SHALL define explicit behavior for clipboard requests that require confirmation or use clipboard namespaces that macOS does not natively expose.

#### Scenario: Clipboard read requires confirmation
- **WHEN** the terminal runtime requests a clipboard read that requires user confirmation
- **THEN** OpenMUX SHALL surface an OpenMUX-owned confirmation path before completing or denying the request

#### Scenario: Selection clipboard is unsupported
- **WHEN** the terminal runtime requests selection clipboard behavior and OpenMUX does not support a macOS selection clipboard namespace
- **THEN** OpenMUX SHALL deny or ignore that request consistently without claiming success

### Requirement: Clipboard commands are available through AppKit command routing
OpenMUX SHALL expose standard AppKit command routing for terminal clipboard actions.

#### Scenario: Edit menu invokes Paste
- **WHEN** the user selects Paste from the macOS Edit menu while a terminal pane is focused
- **THEN** OpenMUX SHALL route Paste to the focused terminal pane

#### Scenario: Keyboard shortcut invokes Copy
- **WHEN** the user presses Command-C while a terminal pane with selected terminal content is focused
- **THEN** OpenMUX SHALL route Copy to the focused terminal pane

### Requirement: Clipboard behavior remains bridge-local
OpenMUX SHALL keep runtime clipboard API details inside `OmuxTerminalBridge` and expose only OpenMUX-native behavior to AppShell.

#### Scenario: AppShell routes a clipboard command
- **WHEN** AppShell routes Copy, Paste, or Select All to a focused terminal pane
- **THEN** AppShell SHALL NOT access libghostty pointers, enums, or C callback payloads

### Requirement: Fallback clipboard behavior remains functional
Fallback terminal panes SHALL preserve basic macOS clipboard behavior where runtime terminal clipboard APIs are unavailable.

#### Scenario: Fallback pane pastes text
- **WHEN** a fallback terminal pane is focused and the user invokes Paste
- **THEN** OpenMUX SHALL send standard clipboard text to the fallback terminal session

#### Scenario: Fallback pane copies selected text
- **WHEN** a fallback terminal pane has selected visible text and the user invokes Copy
- **THEN** OpenMUX SHALL place the selected text on the standard macOS clipboard
