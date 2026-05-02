## ADDED Requirements

### Requirement: Run-command submits commands in live terminal sessions
Interactive terminal sessions SHALL execute commands sent through run-command by inserting the command text into the targeted live session and submitting it with the terminal backend's correct Return/Enter mechanism.

#### Scenario: Runtime-backed pane executes run command
- **WHEN** a client sends run-command to a Ghostty-backed live terminal session
- **THEN** the command is submitted for shell execution without requiring the user to press Return manually

#### Scenario: Fallback pane executes run command
- **WHEN** a client sends run-command to a fallback live terminal session
- **THEN** the command is submitted for shell execution without requiring the user to press Return manually

### Requirement: Raw send-text does not imply command submission
Interactive terminal sessions SHALL support raw text insertion separately from command execution.

#### Scenario: Send text leaves prompt editable
- **WHEN** a client sends raw text to a live terminal session
- **THEN** the text appears in the target terminal input stream without an implicit Return/Enter submission

#### Scenario: Send text preserves keyboard input semantics
- **WHEN** raw text is sent by automation
- **THEN** OpenMUX does not reinterpret that text as physical keyboard input, Option/Alt combinations, dead keys, compose sequences, or IME composition
