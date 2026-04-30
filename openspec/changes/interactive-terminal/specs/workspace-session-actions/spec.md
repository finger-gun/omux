## MODIFIED Requirements

### Requirement: The first action set SHALL cover core workspace control
The system SHALL support core workspace/session actions for opening a workspace, creating a tab, splitting a pane, focusing a session, and sending commands or text into a persistent live session.

#### Scenario: Core workspace control is available
- **WHEN** a user or tool requests one of the first-phase workspace/session actions
- **THEN** the system can perform that action against the active workspace/session model without bypassing the app shell or control-plane contracts

### Requirement: Workspace/session actions SHALL target live terminal sessions
The system SHALL bind workspace/session actions to active terminal-backed panes and persistent interactive sessions rather than placeholder shell state or one-off command execution.

#### Scenario: Run-command targets an ongoing session
- **WHEN** a command is sent to a workspace session
- **THEN** the system injects it into the targeted live terminal session without creating a separate transient shell process

## ADDED Requirements

### Requirement: Shared actions SHALL preserve session continuity across UI and automation
The system SHALL ensure that UI interactions and `omux` automation target the same ongoing pane session so session state, working directory, and shell history remain consistent.

#### Scenario: UI typing and CLI command injection share session state
- **WHEN** a user types in a pane and later an automation tool sends a command to that same session
- **THEN** both operations affect the same ongoing interactive shell state
