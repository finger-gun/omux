## MODIFIED Requirements

### Requirement: Workspace actions SHALL be shared by UI and CLI
The system SHALL expose workspace, pane-stack, and session action sets through shared OpenMUX operations that can be invoked by both the native shell and `omux`, and successful shared actions SHALL emit corresponding OpenMUX-native action events.

#### Scenario: The same workspace action is available across entry points
- **WHEN** a user or tool opens a workspace, focuses a session, requests a split, or changes the active local pane tab
- **THEN** the app and CLI operate through the same underlying workspace/session action model

#### Scenario: Successful shared action emits a matching event
- **WHEN** a shared workspace or session action succeeds through either the UI or CLI
- **THEN** OpenMUX emits the corresponding OpenMUX-native action event for that completed action

## ADDED Requirements

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
