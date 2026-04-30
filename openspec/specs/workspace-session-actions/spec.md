# workspace-session-actions Specification

## Purpose
TBD - created by archiving change workspace-shell. Update Purpose after archive.

## Requirements

### Requirement: Workspace actions SHALL be shared by UI and CLI
The system SHALL expose workspace, pane-stack, and session action sets through shared OpenMUX operations that can be invoked by both the native shell and `omux`.

#### Scenario: The same workspace action is available across entry points
- **WHEN** a user or tool opens a workspace, focuses a session, requests a split, or changes the active local pane tab
- **THEN** the app and CLI operate through the same underlying workspace/session action model

### Requirement: The first action set SHALL cover core workspace control
The system SHALL support core workspace/session actions for opening a workspace, creating a top-level tab, splitting the active local pane tab, focusing a session, running a command in a session, and creating/focusing/closing local pane tabs inside the focused pane stack.

#### Scenario: Core workspace control is available
- **WHEN** a user or tool requests one of the first-phase workspace/session actions
- **THEN** the system can perform that action without bypassing the app shell or control-plane contracts

### Requirement: Workspace/session actions SHALL target live terminal sessions
The system SHALL bind workspace/session actions to active terminal-backed local pane tabs and sessions rather than placeholder shell state.

#### Scenario: Run-command targets a real session
- **WHEN** a command is sent to a workspace session
- **THEN** the system applies it to the targeted live terminal-backed local pane tab session

### Requirement: Shared actions SHALL preserve session continuity across UI and automation
The system SHALL ensure that UI interactions and `omux` automation target the same ongoing pane session so session state, working directory, and shell history remain consistent.

#### Scenario: UI typing and CLI command injection share session state
- **WHEN** a user types in a pane and later an automation tool sends a command to that same session
- **THEN** both operations affect the same ongoing interactive shell state
