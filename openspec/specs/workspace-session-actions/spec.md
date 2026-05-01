# workspace-session-actions Specification

## Purpose
TBD - created by archiving change workspace-shell. Update Purpose after archive.

## Requirements

### Requirement: Workspace actions SHALL be shared by UI and CLI
The system SHALL expose workspace, pane-stack, and session action sets through shared OpenMUX operations that can be invoked by both the native shell and `omux`, and successful shared actions SHALL emit corresponding OpenMUX-native action events.

#### Scenario: The same workspace action is available across entry points
- **WHEN** a user or tool opens a workspace, focuses a session, requests a split, or changes the active local pane tab
- **THEN** the app and CLI operate through the same underlying workspace/session action model

#### Scenario: Successful shared action emits a matching event
- **WHEN** a shared workspace or session action succeeds through either the UI or CLI
- **THEN** OpenMUX emits the corresponding OpenMUX-native action event for that completed action

### Requirement: The first action set SHALL cover core workspace control
The system SHALL support core workspace/session actions for opening a workspace, creating a top-level tab, splitting the active local pane tab, focusing a session, running a command in a session, and creating/focusing/closing local pane tabs inside the focused pane stack.

#### Scenario: Core workspace control is available
- **WHEN** a user or tool requests one of the first-phase workspace/session actions
- **THEN** the system can perform that action without bypassing the app shell or control-plane contracts

### Requirement: The first action set SHALL emit corresponding action events
The system SHALL emit corresponding action events for the first shared workspace/session action set: opening a workspace, creating a top-level tab, splitting the active local pane tab, creating/focusing/closing local pane tabs, focusing a session, running a command in a session, raising a notification, and restoring a workspace.

#### Scenario: Pane split emits a parity event
- **WHEN** the shared split action creates a new pane
- **THEN** OpenMUX emits `pane.split` for that completed action

#### Scenario: Session focus emits a parity event
- **WHEN** a shared session-focus action succeeds
- **THEN** OpenMUX emits `session.focused` for that completed action

#### Scenario: Invalid action emits no parity event
- **WHEN** a requested shared action is rejected or results in no state change
- **THEN** OpenMUX does not emit a success-shaped action event for that request

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

### Requirement: Workspace actions SHALL support direct ordered workspace switching
The system SHALL support direct switching to open workspaces by visible workspace order so keyboard-driven users can jump to the first nine visible workspaces without traversing the sidebar manually.

#### Scenario: User jumps to a numbered workspace
- **WHEN** the shell invokes a direct workspace-switch action for positions `1` through `9`
- **THEN** the corresponding visible workspace becomes active if one exists at that position

#### Scenario: Missing numbered workspace is ignored safely
- **WHEN** the shell invokes a direct workspace-switch action for a position that has no visible workspace
- **THEN** the active workspace remains unchanged

### Requirement: Workspace actions SHALL support previous-active workspace recall
The system SHALL track enough shell-owned workspace activation history to let the user return to the previous active workspace with a dedicated command.

#### Scenario: User returns to the previous active workspace
- **WHEN** the shell invokes the previous-workspace action after the user has switched from one workspace to another
- **THEN** the workspace that was active immediately before the current one becomes active again

#### Scenario: Previous-workspace command is inert without history
- **WHEN** the shell invokes the previous-workspace action before any prior workspace switch exists
- **THEN** the active workspace remains unchanged
