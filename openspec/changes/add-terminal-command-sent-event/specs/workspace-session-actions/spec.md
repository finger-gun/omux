## ADDED Requirements

### Requirement: Shared terminal input actions SHALL emit input-sent lifecycle events
Workspace/session actions that forward terminal input SHALL emit `terminal.inputSent` after input is successfully delivered to the targeted live terminal session.

#### Scenario: CLI run command emits input-sent
- **WHEN** `omux run` successfully sends command text and Return to a resolved live pane or session
- **THEN** OpenMUX emits one action-scoped `terminal.inputSent` event for the submitted command text

#### Scenario: Send-text emits input-sent
- **WHEN** `send-text` inserts arbitrary text into a terminal session
- **THEN** OpenMUX emits `terminal.inputSent` for the forwarded text

#### Scenario: UI typed input does not emit input-sent
- **WHEN** a native terminal pane forwards user-typed text or terminal key input to Ghostty
- **THEN** OpenMUX does not emit per-character or per-key `terminal.inputSent` events

### Requirement: Failed input forwarding SHALL NOT emit input-sent
Workspace/session actions SHALL emit input-sent only for successful input delivery to a live terminal session.

#### Scenario: Missing target emits no input-sent
- **WHEN** an input action targets a missing pane, session, workspace, or tab
- **THEN** OpenMUX rejects the action without emitting `terminal.inputSent`

#### Scenario: Bridge delivery failure emits no input-sent
- **WHEN** the terminal bridge fails to deliver input to the runtime-backed pane
- **THEN** OpenMUX does not emit `terminal.inputSent` and surfaces the failure through the existing action error path
