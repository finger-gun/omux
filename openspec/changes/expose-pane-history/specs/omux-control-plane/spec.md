## ADDED Requirements

### Requirement: Control plane exposes bounded terminal history snapshots
The control plane SHALL expose a local request/response operation that returns bounded terminal history snapshots for live OpenMUX panes using OpenMUX-native workspace, tab, pane, and session identifiers. The operation SHALL NOT expose Ghostty surface identifiers or Ghostty-specific point/range types.

#### Scenario: History request uses OpenMUX-native topology
- **WHEN** a client requests terminal history for one or more panes
- **THEN** the response groups each history snapshot with workspace ID/name, tab ID/title, pane ID/title, session ID, and working directory when available

#### Scenario: History request does not leak terminal engine details
- **WHEN** a client receives a history response
- **THEN** the response contains OpenMUX-native fields and no direct libghostty enum names, surface IDs, or C API payloads

### Requirement: History reads support active workspace, pane, and all-workspace scopes
The control plane SHALL allow history reads scoped to the active workspace panes, to a specific pane ID, or to all live panes across all workspaces and tabs.

#### Scenario: Active workspace scope returns current panes
- **WHEN** a client requests history without an explicit scope
- **THEN** the response contains bounded history items for live panes in the active workspace

#### Scenario: Pane scope returns one pane
- **WHEN** a client requests history for a specific pane ID
- **THEN** the response contains history for that pane only or a structured failure if the pane ID is unknown

#### Scenario: All scope returns all live panes
- **WHEN** a client requests history for all panes
- **THEN** the response contains bounded history items grouped by workspace and tab for every live pane that can be inspected

### Requirement: History responses report bounds and availability
Each control-plane history item SHALL report captured text plus line count, byte count, truncation status, and an explicit unavailable reason when the pane history cannot be captured.

#### Scenario: Captured history includes bounds metadata
- **WHEN** a pane history snapshot is captured successfully
- **THEN** the item includes text, line count, byte count, and whether the text was truncated by requested or implementation-defined limits

#### Scenario: Unavailable pane history is explicit
- **WHEN** a pane exists but its live terminal history cannot be captured
- **THEN** the item includes the pane metadata and an unavailable reason instead of silently returning empty history as success

### Requirement: CLI exposes terminal history through `omux history`
The `omux` CLI SHALL expose terminal history through the local control plane with `omux history`, `omux history <pane-id>`, and `omux history all`.

#### Scenario: No-argument history command lists active workspace panes
- **WHEN** a user runs `omux history`
- **THEN** the CLI requests active-workspace history through the control plane and prints bounded history for the current workspace panes

#### Scenario: Pane history command targets exact pane
- **WHEN** a user runs `omux history <pane-id>`
- **THEN** the CLI requests history for that pane and prints only that pane's bounded history

#### Scenario: All history command lists every pane
- **WHEN** a user runs `omux history all`
- **THEN** the CLI requests all-workspace history and prints bounded history grouped by workspace, tab, and pane

### Requirement: CLI history output supports human and machine consumption
The `omux history` command SHALL provide a readable grouped default output and a machine-readable JSON output mode for hook handlers and scripts.

#### Scenario: Human output includes topology headers
- **WHEN** a user runs `omux history` without JSON output mode
- **THEN** the CLI prints pane history with workspace, tab, pane, session, and cwd headers before each text block

#### Scenario: JSON output preserves structured response
- **WHEN** a hook handler or script requests JSON output for history
- **THEN** the CLI prints the structured control-plane response without requiring the caller to parse human headers

### Requirement: History commands are read-only
History requests SHALL be read-only and SHALL NOT send captured history to terminal input, mutate pane state, persist scrollback, or create UI elements.

#### Scenario: History command does not affect terminal input
- **WHEN** a user or hook calls `omux history`
- **THEN** OpenMUX reads terminal history without sending any text to the live shell or modifying the terminal buffer

#### Scenario: History command does not restore UI scrollback
- **WHEN** a history request succeeds
- **THEN** OpenMUX does not render that history in pane chrome or add it to workspace persistence snapshots
