## ADDED Requirements

### Requirement: Agent adapters sync normalized session rows
The system SHALL use one adapter per supported agent to sync that agent's local session history into normalized Agent Sessions rows.

#### Scenario: Adapter syncs Copilot sessions
- **WHEN** the Copilot adapter syncs from `session-store.db`
- **THEN** it SHALL normalize each Copilot session row using the session id, cwd, summary, and updated timestamp from the `sessions` table

#### Scenario: Adapter syncs file-based agents
- **WHEN** an adapter reads file-based history such as Codex, Gemini, or Claude
- **THEN** it SHALL normalize each discovered session into the same Agent Sessions row shape

### Requirement: Agent Sessions persist one normalized index table
The system SHALL persist Agent Sessions in a single normalized SQLite table containing session id, raw id, agent, source kind, source path, cwd, title, updated datetime, deleted flag, and indexed datetime.

#### Scenario: Session is inserted
- **WHEN** an adapter discovers a new session
- **THEN** the system SHALL insert one normalized row for that session

#### Scenario: Session is updated
- **WHEN** an adapter re-discovers an existing session
- **THEN** the system SHALL update the normalized row's metadata without requiring auxiliary resume snapshot or transcript tables

### Requirement: Deleted Agent Sessions are hidden locally
The system SHALL represent deletion as a local `deleted` flag in the Agent Sessions index.

#### Scenario: User deletes a session
- **WHEN** the user deletes an Agent Session from OpenMUX
- **THEN** the system SHALL mark the normalized row as deleted and SHALL NOT delete the upstream agent's real session data

#### Scenario: Deleted session is reindexed
- **WHEN** an adapter re-discovers a session whose normalized row is deleted
- **THEN** the system SHALL update metadata as needed while preserving `deleted = true`

#### Scenario: Sessions are listed
- **WHEN** the UI, CLI, or control plane lists Agent Sessions
- **THEN** the system SHALL exclude rows where `deleted = true`

### Requirement: Resume behavior is adapter and config driven
The system SHALL compute resume commands from the normalized row's agent/raw session id and configured agent resume behavior.

#### Scenario: User opens an inactive session
- **WHEN** the user opens an inactive Agent Session
- **THEN** the system SHALL compute and run the agent's resume command without reading a persisted resume snapshot

### Requirement: Workspace filtering derives from cwd roots
The system SHALL derive Agent Session workspace membership at query time using normalized cwd prefix matching against the current workspace root.

#### Scenario: Workspace-scoped sessions are queried
- **WHEN** the sidebar queries sessions for a workspace rooted at `/path/project`
- **THEN** the query SHALL include sessions whose cwd is `/path/project` or starts with `/path/project/`

#### Scenario: Session has unknown cwd
- **WHEN** a session row has no cwd
- **THEN** workspace-scoped queries SHALL exclude it and all-workspace queries MAY include it

### Requirement: Active status is runtime UI state
The system SHALL derive active Agent Session status from runtime pane/session state rather than the Agent Sessions index.

#### Scenario: Session is resumed in a pane
- **WHEN** OpenMUX opens or resumes an Agent Session in a pane
- **THEN** the UI SHALL associate that pane with the Agent Session for active/focus behavior

#### Scenario: Pane status changes
- **WHEN** the associated pane's progress/status changes
- **THEN** the Agent Sessions sidebar SHALL reflect the same runtime status indicator without writing active state to the Agent Sessions database

### Requirement: Index refresh is non-blocking and stable
The system SHALL perform Agent Sessions indexing in the background and update visible UI rows only when indexed result data changes.

#### Scenario: Refresh runs
- **WHEN** an Agent Sessions refresh or reindex is running
- **THEN** the UI SHALL remain responsive and SHALL keep existing rows visible until new result data is ready

#### Scenario: Result set is unchanged
- **WHEN** a refresh completes with the same visible rows
- **THEN** the sidebar SHALL NOT rebuild rows or reset scroll position
