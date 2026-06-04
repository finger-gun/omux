## ADDED Requirements

### Requirement: Follow-up parity transitions SHALL emit action events
The system SHALL emit corresponding OpenMUX-native action events for successful follow-up parity transitions that already exist as shared actions or documented user-visible state changes: workspace close, pane remove, pane alias set, pane alias clear, and config reload completion.

#### Scenario: Workspace close emits action event
- **WHEN** a workspace close action succeeds through the native shell or `omux workspace-close`
- **THEN** the event stream emits `workspace.closed` with the closed workspace identifier and workspace path payload

#### Scenario: Pane remove emits action event
- **WHEN** a pane remove action succeeds through the native shell or `omux pane-remove`
- **THEN** the event stream emits `pane.removed` with the affected workspace, tab, pane, and session identifiers when that context exists

#### Scenario: Pane alias set emits action event
- **WHEN** a pane alias is set successfully through the shared alias action path
- **THEN** the event stream emits `pane.aliasSet` with the pane identifier and alias payload

#### Scenario: Pane alias clear emits action event
- **WHEN** a pane alias is cleared successfully through the shared alias action path
- **THEN** the event stream emits `pane.aliasCleared` with the pane identifier and no stale alias value

#### Scenario: Config reload completion emits action event
- **WHEN** OpenMUX successfully completes a config apply/reload pass triggered by command or file watching
- **THEN** the event stream emits `config.reloaded` with OpenMUX-native source and applied-change payload fields

### Requirement: Follow-up parity action events SHALL remain success-shaped
The follow-up parity action events SHALL follow the same observational contract as the first-wave action events and SHALL NOT be emitted for failed or inert outcomes.

#### Scenario: Failed workspace close emits no success event
- **WHEN** a workspace close request is rejected or cannot change state
- **THEN** the event stream does not emit `workspace.closed`

#### Scenario: Failed config reload emits no success event
- **WHEN** a config apply/reload attempt fails validation and the previous effective configuration remains active
- **THEN** the event stream does not emit `config.reloaded`
