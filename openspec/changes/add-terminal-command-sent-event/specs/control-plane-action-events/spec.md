## ADDED Requirements

### Requirement: The local event stream SHALL publish terminal input-sent events
The local control-plane event stream SHALL publish action-scoped `terminal.inputSent` events through the same `omux events` subscription surface used for other terminal runtime events.

#### Scenario: Subscriber receives input-sent event
- **WHEN** OpenMUX emits an input-sent terminal lifecycle event for a live terminal session
- **THEN** an `omux events` subscriber receives `terminal.inputSent` with workspace, tab, pane, session, and structured payload fields

#### Scenario: Input-sent payload is structured
- **WHEN** `terminal.inputSent` is published
- **THEN** its payload includes `text`, `key`, `keyCode`, `modifiers`, `route`, and `source`, using null values where a field is not available

### Requirement: Input-sent events SHALL be additive to existing action events
The system SHALL keep existing shared action events such as `command.started` while adding `terminal.inputSent` as a terminal input lifecycle event.

#### Scenario: Run command emits input and action observations
- **WHEN** `omux run` successfully submits text and Return to a live terminal session
- **THEN** subscribers can observe one action-scoped input-sent terminal event and the existing `command.started` action event without either event replacing the other
