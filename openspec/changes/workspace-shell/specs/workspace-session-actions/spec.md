## ADDED Requirements

### Requirement: Workspace actions SHALL be shared by UI and CLI
The system SHALL expose the first usable workspace/session action set through shared OpenMUX operations that can be invoked by both the native shell and `omux`.

#### Scenario: The same workspace action is available across entry points
- **WHEN** a user or tool opens a workspace, focuses a session, or requests a split
- **THEN** the app and CLI operate through the same underlying workspace/session action model

### Requirement: The first action set SHALL cover core workspace control
The system SHALL support core workspace/session actions for opening a workspace, creating a tab, splitting a pane, focusing a session, and running a command in a session.

#### Scenario: Core workspace control is available
- **WHEN** a user or tool requests one of the first-phase workspace/session actions
- **THEN** the system can perform that action without bypassing the app shell or control-plane contracts

### Requirement: Workspace/session actions SHALL target live terminal sessions
The system SHALL bind workspace/session actions to active terminal-backed panes and sessions rather than placeholder shell state.

#### Scenario: Run-command targets a real session
- **WHEN** a command is sent to a workspace session
- **THEN** the system applies it to the targeted live terminal-backed session
