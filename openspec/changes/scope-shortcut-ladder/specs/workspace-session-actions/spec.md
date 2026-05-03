## ADDED Requirements

### Requirement: Shared actions SHALL cover workspace and pane removal
Workspace/session actions SHALL expose workspace close/delete and pane remove operations through shared OpenMUX operations that can be invoked by both the native shell and `omux`.

#### Scenario: Workspace close is shared
- **WHEN** the native shell or CLI requests closing a workspace
- **THEN** OpenMUX closes the targeted workspace through the shared workspace action model

#### Scenario: Pane remove is shared
- **WHEN** the native shell or CLI requests removing a pane
- **THEN** OpenMUX removes the targeted or focused pane through the shared workspace action model without bypassing pane-stack rules

#### Scenario: Invalid remove action emits no success event
- **WHEN** a workspace close or pane remove request is invalid or cannot change state
- **THEN** OpenMUX returns a structured failure and does not emit a success-shaped action event
