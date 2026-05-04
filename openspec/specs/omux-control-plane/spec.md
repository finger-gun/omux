# omux-control-plane Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.
## Requirements
### Requirement: The CLI controls the app through a local RPC contract
The system SHALL expose a local control plane between the OpenMUX desktop app and the `omux` CLI using JSON-RPC over a Unix domain socket for both capability requests and local event subscriptions.

#### Scenario: CLI operations use the public control boundary
- **WHEN** the `omux` CLI requests app-level behavior
- **THEN** it communicates through the local JSON-RPC control contract rather than private in-process coupling

#### Scenario: CLI event subscribers use the public control boundary
- **WHEN** the `omux` CLI subscribes to streamed OpenMUX events
- **THEN** it receives those events through the same local control-plane contract rather than a separate private transport

### Requirement: Control-plane operations are capability-oriented
The control plane SHALL expose app operations in terms of OpenMUX capabilities such as opening workspaces, focusing panes, sending text, raising notifications, and restoring sessions.

#### Scenario: RPC commands map to OpenMUX behavior
- **WHEN** automation targets the desktop application
- **THEN** the available operations align with OpenMUX concepts instead of low-level terminal-engine details

### Requirement: The control plane remains local-first and lightweight
The system SHALL treat the app/CLI control plane as a local desktop boundary optimized for inspectability and minimal operational overhead.

#### Scenario: Local automation avoids unnecessary service complexity
- **WHEN** the control plane is used on a developer workstation
- **THEN** it does not require distributed-service infrastructure or unnecessary background processes beyond the local app service itself

### Requirement: Terminal event contracts are defined in OpenMUX-native control-plane terms
The control plane SHALL define terminal event names and payload shapes in OpenMUX-native terms for local automation and streamed event delivery surfaces. These event contracts SHALL avoid Ghostty-specific enums, tags, and payload structs.

#### Scenario: Control-plane terminal event names are product-level contracts
- **WHEN** OpenMUX defines a control-plane event for terminal cwd, command completion, progress, or renderer health
- **THEN** the event name and payload shape are expressed in OpenMUX-native terms instead of Ghostty callback identifiers

#### Scenario: Terminal events remain stable inside a broader event stream
- **WHEN** terminal runtime events are published alongside shared action events through `omux events`
- **THEN** the `terminal.*` event meanings and payload fields remain stable because they are defined independently of the transport and of non-terminal event families

### Requirement: The control plane SHALL stream OpenMUX-native action events
The control plane SHALL stream OpenMUX-native event notifications for successful shared workspace, pane, tab, session, command, and notification actions through the same local event surface used by terminal runtime events.

#### Scenario: Subscriber observes a pane split action
- **WHEN** a shared pane split action succeeds
- **THEN** the control plane publishes a `pane.split` event with OpenMUX-native identifiers and payload fields

#### Scenario: Subscriber observes a restored workspace
- **WHEN** a shared workspace restore action succeeds
- **THEN** the control plane publishes a `workspace.restored` event through the local event stream

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

### Requirement: Control plane exposes bounded terminal history snapshots
The control plane SHALL expose a local request/response operation that returns bounded terminal history snapshots for OpenMUX panes using OpenMUX-native workspace, tab, pane, and session identifiers. The operation SHALL use persisted per-pane history when available and live terminal history when available. The operation SHALL NOT expose Ghostty surface identifiers or Ghostty-specific point/range types.

#### Scenario: History request uses OpenMUX-native topology
- **WHEN** a client requests terminal history for one or more panes
- **THEN** the response groups each history snapshot with workspace ID/name, tab ID/title, pane ID/title, session ID, and working directory when available

#### Scenario: History request does not leak terminal engine details
- **WHEN** a client receives a history response
- **THEN** the response contains OpenMUX-native fields and no direct libghostty enum names, surface IDs, or C API payloads

#### Scenario: Restarted pane can return persisted pane history
- **WHEN** a workspace is restored after app restart and contains bounded persisted history for a pane
- **THEN** a history response for that pane includes the persisted pane history without requiring the previous live terminal surface to still exist

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
History requests SHALL be read-only and SHALL NOT send captured history to terminal input, mutate pane state, or create UI elements. Persisting bounded pane history SHALL occur as part of workspace state persistence, not as a side effect of invoking `omux history`.

#### Scenario: History command does not affect terminal input
- **WHEN** a user or hook calls `omux history`
- **THEN** OpenMUX reads terminal history without sending any text to the live shell or modifying the terminal buffer

#### Scenario: History command does not restore UI scrollback
- **WHEN** a history request succeeds
- **THEN** OpenMUX does not render that history in pane chrome or send it to the terminal buffer

### Requirement: Persisted history is pane-scoped
OpenMUX SHALL persist bounded history independently for each pane/pane-tab terminal record rather than storing one combined workspace history blob.

#### Scenario: Pane-specific persisted history remains targetable
- **WHEN** a workspace with multiple pane tabs is persisted and restored
- **THEN** `omux history <pane-id>` returns the bounded history for that pane ID without mixing output from sibling panes or pane tabs

### Requirement: Control plane SHALL expose pane navigation capabilities
The control plane SHALL expose capability-oriented JSON-RPC methods for cycling pane-local tabs and panes using OpenMUX-native workspace, tab, pane stack, pane, and session identifiers.

#### Scenario: Pane-local tab next operation returns focused context
- **WHEN** a client invokes the next pane-local tab operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Pane-local tab previous operation returns focused context
- **WHEN** a client invokes the previous pane-local tab operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Pane next operation returns focused context
- **WHEN** a client invokes the next pane operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Pane previous operation returns focused context
- **WHEN** a client invokes the previous pane operation
- **THEN** the response identifies the focused workspace, tab, pane stack, pane, and session after navigation

#### Scenario: Navigation target failure is explicit
- **WHEN** a navigation request cannot resolve a valid workspace, tab, pane stack, pane, or session target
- **THEN** the control plane returns a structured failure instead of silently choosing another target

### Requirement: CLI SHALL expose every new shared navigation action
The `omux` CLI SHALL expose commands for opening the configured default root and for cycling pane-local tabs and panes through the public control-plane contract.

#### Scenario: CLI opens configured root
- **WHEN** the user runs `omux open` without a path
- **THEN** the CLI sends a workspace open request that allows the app to resolve the configured default root

#### Scenario: CLI cycles pane-local tabs
- **WHEN** the user runs `omux pane-tab-next` or `omux pane-tab-prev`
- **THEN** the CLI invokes the corresponding pane-local tab navigation method through the control plane

#### Scenario: CLI cycles panes
- **WHEN** the user runs `omux pane-next` or `omux pane-prev`
- **THEN** the CLI invokes the corresponding pane navigation method through the control plane

### Requirement: Control plane SHALL expose workspace close and pane remove commands
The local JSON-RPC control plane and `omux` CLI SHALL expose additive commands for closing workspaces and removing panes.

#### Scenario: CLI closes active workspace by default
- **WHEN** a user runs `omux workspace-close` without a workspace ID
- **THEN** the CLI requests closing the active workspace through the local control plane

#### Scenario: CLI closes explicit workspace
- **WHEN** a user runs `omux workspace-close <workspace-id>`
- **THEN** the CLI requests closing that workspace ID through the local control plane

#### Scenario: CLI removes focused pane by default
- **WHEN** a user runs `omux pane-remove` without a target selector
- **THEN** the CLI requests removal of the focused pane through the local control plane

#### Scenario: CLI removes targetable pane
- **WHEN** a user runs `omux pane-remove` with a supported terminal target selector
- **THEN** the CLI requests removal of the resolved pane through the local control plane and receives structured success or failure

#### Scenario: Existing creation commands remain available
- **WHEN** users invoke existing creation commands including `omux open`, `omux split`, and `omux pane-tab`
- **THEN** those commands continue to work without being replaced by the new close/remove commands

