## MODIFIED Requirements

### Requirement: Agent adapters sync normalized session rows
The system SHALL use built-in adapters and plugin-declared external adapters to sync local agent session history into normalized Agent Sessions rows.

#### Scenario: Adapter syncs Copilot sessions
- **WHEN** the Copilot adapter syncs from `session-store.db`
- **THEN** it SHALL normalize each Copilot session row using the session id, cwd, summary, and updated timestamp from the `sessions` table

#### Scenario: Adapter syncs bundled file-based agents
- **WHEN** a bundled adapter reads file-based history such as Codex or Gemini
- **THEN** it SHALL normalize each discovered session into the same Agent Sessions row shape

#### Scenario: Plugin adapter syncs normalized rows
- **WHEN** an installed plugin manifest declares an Agent Sessions adapter and its callback exits successfully with normalized JSON rows on stdout
- **THEN** the system SHALL validate and upsert those rows into the Agent Sessions index

#### Scenario: External adapter registers its own agent name
- **WHEN** a plugin Agent Sessions adapter does not emit an explicit per-row agent
- **THEN** the system SHALL use the plugin's registered command name as the normalized Agent Sessions agent name

#### Scenario: External adapter uses a non-built-in agent name
- **WHEN** an external adapter emits rows for an agent name not built into OpenMUX
- **THEN** the system SHALL preserve that agent name for list, search, filtering, and display

#### Scenario: External adapter fails
- **WHEN** a plugin Agent Sessions adapter exits nonzero or emits invalid JSON
- **THEN** the system SHALL report a reindex warning for that adapter and SHALL continue indexing other adapters

### Requirement: Agent Sessions adapter participation is configurable
The system SHALL allow users to enable or disable built-in and external Agent Sessions adapters.

#### Scenario: Built-in adapter disabled
- **WHEN** `[agent-sessions.agents.<agent>] enabled = false`
- **THEN** the system SHALL NOT run the built-in adapter for that agent during reindex

#### Scenario: External adapters enabled by default
- **WHEN** `[agent-sessions] external_adapters_enabled` is absent
- **THEN** the system SHALL run plugin-declared external adapters during normal Agent Sessions reindex

#### Scenario: External adapters disabled globally
- **WHEN** `[agent-sessions] external_adapters_enabled = false`
- **THEN** the system SHALL NOT run plugin-declared external adapters during normal Agent Sessions reindex

#### Scenario: External adapter disabled individually
- **WHEN** `[agent-sessions.external.<adapter>] enabled = false`
- **THEN** the system SHALL NOT run that external adapter during normal Agent Sessions reindex
