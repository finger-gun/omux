## ADDED Requirements

### Requirement: Control-plane event streams do not block commands
The control plane SHALL handle long-lived event stream connections without blocking unrelated request/response commands on separate connections.

#### Scenario: Events subscriber remains connected while command completes
- **WHEN** one client is connected to the event stream
- **THEN** another client can complete a control-plane command without waiting for the stream client to disconnect

#### Scenario: Multiple event subscribers do not monopolize the server
- **WHEN** multiple clients subscribe to control-plane events
- **THEN** the server still accepts and handles new request/response clients

### Requirement: Control-plane targets are explicit and OpenMUX-native
The control plane SHALL accept terminal action targets using explicit OpenMUX-native selector fields for session, pane, tab, workspace, or focused terminal selection. A selector SHALL resolve to one live terminal session before a terminal-mutating action executes.

#### Scenario: Session selector targets exact session
- **WHEN** a request targets a terminal action by session ID
- **THEN** the action applies to that exact live session

#### Scenario: Pane selector resolves active pane session
- **WHEN** a request targets a terminal action by pane ID
- **THEN** the action applies to the active local pane-tab session in that pane

#### Scenario: Workspace selector resolves focused workspace session
- **WHEN** a request targets a terminal action by workspace ID
- **THEN** the action applies to the focused terminal session in that workspace

#### Scenario: Invalid selector fails explicitly
- **WHEN** a request target cannot be resolved to a live terminal session
- **THEN** the control plane returns a structured failure instead of silently choosing another terminal

### Requirement: Control plane exposes raw terminal text input
The control plane SHALL expose a terminal text-input operation that sends caller-provided text to a resolved terminal target without appending Return or submitting a command.

#### Scenario: Send text inserts without execution
- **WHEN** a client sends text to a terminal target through the control plane
- **THEN** OpenMUX inserts that text into the target terminal input stream without adding an implicit command submission

#### Scenario: Send text is distinct from run command
- **WHEN** a client wants command execution
- **THEN** it uses the run-command operation rather than relying on raw text input

### Requirement: Control plane exposes live topology discovery
The control plane SHALL expose machine-readable discovery for open workspaces, tabs, panes, pane stacks, and sessions, including focused IDs where available.

#### Scenario: CLI can list targetable sessions
- **WHEN** a CLI or hook script requests live terminal topology
- **THEN** the response includes enough workspace, tab, pane, and session IDs to target a later action without scraping UI text

#### Scenario: Full workspace listing includes focused terminal IDs
- **WHEN** a client requests detailed workspace state
- **THEN** each workspace entry includes focused tab, pane, pane-stack, and session IDs when those entities exist

### Requirement: Control-plane action results are chainable
The control plane SHALL return structured result objects for automation actions that include relevant created, focused, or targeted OpenMUX IDs.

#### Scenario: Split result includes created terminal identifiers
- **WHEN** a split action creates a new terminal pane/session
- **THEN** the response includes the created pane ID and session ID

#### Scenario: Run command result includes target identifiers
- **WHEN** a run-command action succeeds
- **THEN** the response includes the workspace, tab, pane, and session IDs that received the command
