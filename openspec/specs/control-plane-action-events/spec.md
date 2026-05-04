# control-plane-action-events Specification

## Purpose

Define the OpenMUX-native event contract for shared actions and terminal events on the local control-plane stream.
## Requirements
### Requirement: The local event stream SHALL publish shared action events and terminal events through one subscription surface
The system SHALL stream OpenMUX-native control-plane events through `omux events` using one local subscription surface that can publish both `terminal.*` runtime events and controller-owned shared action events.

#### Scenario: Subscriber receives a shared action event
- **WHEN** a pane split succeeds through a shared OpenMUX action path
- **THEN** an `omux events` subscriber receives a `pane.split` event from the same local stream used for terminal events

#### Scenario: Subscriber continues receiving terminal runtime events
- **WHEN** the embedded runtime emits a supported terminal title change
- **THEN** an `omux events` subscriber receives the corresponding `terminal.titleChanged` event from that same subscription surface

### Requirement: First-wave short commands SHALL have corresponding action events
The system SHALL emit a corresponding action event for each successful first-wave short command that mutates OpenMUX state or triggers shell-owned behavior: `open`, `tab`, `split`, `pane-tab`, `pane-tab-focus`, `pane-tab-close`, `focus`, `run`, `notify`, and `restore`.

#### Scenario: Open workspace emits an action event
- **WHEN** `omux open <path>` succeeds
- **THEN** the event stream emits `workspace.opened` with the new workspace context and the opened path in the payload

#### Scenario: Run command emits an action event
- **WHEN** `omux run <session-id> <command>` succeeds
- **THEN** the event stream emits `command.started` with the targeted session context and the submitted command in the payload

### Requirement: Shared UI and CLI actions SHALL emit the same action event contract
The system SHALL emit the same event name and payload shape for a first-wave shared action regardless of whether it was invoked from the native shell or from the `omux` CLI.

#### Scenario: Pane-tab creation uses one event contract across entry points
- **WHEN** a new pane tab is created through either the native shell or `omux pane-tab`
- **THEN** the emitted event uses the same `paneTab.created` name and OpenMUX-native payload shape

### Requirement: Action event context SHALL be sparse and action-appropriate
The system SHALL include only the contextual identifiers that genuinely exist for the emitted action event instead of fabricating terminal-specific context.

#### Scenario: Workspace-opened event carries full created context
- **WHEN** a workspace is opened and creates its initial tab, pane, and session
- **THEN** the emitted `workspace.opened` event includes the relevant workspace, tab, pane, and session identifiers

#### Scenario: Notification event does not invent pane context
- **WHEN** the shell raises a notification through the shared notification action
- **THEN** the emitted `notification.raised` event may omit `tabID`, `paneID`, or `sessionID` if that context does not meaningfully exist

### Requirement: Action-event parity SHALL remain controller-owned and observational
The system SHALL publish first-wave action events only for successful controller-owned outcomes, and the event stream SHALL remain observational rather than serving as a command-input mechanism.

#### Scenario: Failed shared action does not emit a success-shaped event
- **WHEN** `omux focus <session-id>` targets a missing session and the shared action fails
- **THEN** the event stream does not emit `session.focused`

#### Scenario: Action event maps back to a shared action concept
- **WHEN** the event stream emits `paneTab.closed`
- **THEN** that event corresponds to a controller-owned pane-tab close action rather than an arbitrary terminal-side signal

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

