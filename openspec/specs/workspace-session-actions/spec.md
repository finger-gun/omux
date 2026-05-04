# workspace-session-actions Specification

## Purpose
TBD - created by archiving change workspace-shell. Update Purpose after archive.
## Requirements
### Requirement: Workspace actions SHALL be shared by UI and CLI
The system SHALL expose workspace, pane-stack, and session action sets through shared OpenMUX operations that can be invoked by both the native shell and `omux`, and successful shared actions SHALL emit corresponding OpenMUX-native action events.

#### Scenario: The same workspace action is available across entry points
- **WHEN** a user or tool opens a workspace, focuses a session, requests a split, or changes the active local pane tab
- **THEN** the app and CLI operate through the same underlying workspace/session action model

#### Scenario: Successful shared action emits a matching event
- **WHEN** a shared workspace or session action succeeds through either the UI or CLI
- **THEN** OpenMUX emits the corresponding OpenMUX-native action event for that completed action

### Requirement: The first action set SHALL cover core workspace control
The system SHALL support core workspace/session actions for opening a workspace, creating a top-level tab, splitting the active local pane tab, focusing a session, running a command in a session, and creating/focusing/closing local pane tabs inside the focused pane stack.

#### Scenario: Core workspace control is available
- **WHEN** a user or tool requests one of the first-phase workspace/session actions
- **THEN** the system can perform that action without bypassing the app shell or control-plane contracts

### Requirement: The first action set SHALL emit corresponding action events
The system SHALL emit corresponding action events for the first shared workspace/session action set: opening a workspace, creating a top-level tab, splitting the active local pane tab, creating/focusing/closing local pane tabs, focusing a session, running a command in a session, raising a notification, and restoring a workspace.

#### Scenario: Pane split emits a parity event
- **WHEN** the shared split action creates a new pane
- **THEN** OpenMUX emits `pane.split` for that completed action

#### Scenario: Session focus emits a parity event
- **WHEN** a shared session-focus action succeeds
- **THEN** OpenMUX emits `session.focused` for that completed action

#### Scenario: Invalid action emits no parity event
- **WHEN** a requested shared action is rejected or results in no state change
- **THEN** OpenMUX does not emit a success-shaped action event for that request

### Requirement: Workspace/session actions SHALL target live terminal sessions
The system SHALL bind workspace/session actions to active terminal-backed local pane tabs and sessions rather than placeholder shell state.

#### Scenario: Run-command targets a real session
- **WHEN** a command is sent to a workspace session
- **THEN** the system applies it to the targeted live terminal-backed local pane tab session

### Requirement: Shared actions SHALL preserve session continuity across UI and automation
The system SHALL ensure that UI interactions and `omux` automation target the same ongoing pane session so session state, working directory, and shell history remain consistent.

#### Scenario: UI typing and CLI command injection share session state
- **WHEN** a user types in a pane and later an automation tool sends a command to that same session
- **THEN** both operations affect the same ongoing interactive shell state

### Requirement: Workspace actions SHALL support direct ordered workspace switching
The system SHALL support direct switching to open workspaces by visible workspace order so keyboard-driven users can jump to the first nine visible workspaces without traversing the sidebar manually.

#### Scenario: User jumps to a numbered workspace
- **WHEN** the shell invokes a direct workspace-switch action for positions `1` through `9`
- **THEN** the corresponding visible workspace becomes active if one exists at that position

#### Scenario: Missing numbered workspace is ignored safely
- **WHEN** the shell invokes a direct workspace-switch action for a position that has no visible workspace
- **THEN** the active workspace remains unchanged

### Requirement: Workspace actions SHALL support previous-active workspace recall
The system SHALL track enough shell-owned workspace activation history to let the user return to the previous active workspace with a dedicated command.

#### Scenario: User returns to the previous active workspace
- **WHEN** the shell invokes the previous-workspace action after the user has switched from one workspace to another
- **THEN** the workspace that was active immediately before the current one becomes active again

#### Scenario: Previous-workspace command is inert without history
- **WHEN** the shell invokes the previous-workspace action before any prior workspace switch exists
- **THEN** the active workspace remains unchanged

### Requirement: Workspace actions resolve shared terminal targets
Workspace/session actions SHALL resolve shared terminal target selectors into live terminal-backed pane/session contexts before mutating terminal state.

#### Scenario: Focused target follows active UI terminal
- **WHEN** an automation action targets the globally focused terminal
- **THEN** the action applies to the same terminal session that would receive user keyboard input

#### Scenario: Container targets resolve to focused child terminal
- **WHEN** an automation action targets a workspace or tab container
- **THEN** the action applies to that container's focused terminal session

#### Scenario: Pane target resolves to active local pane tab
- **WHEN** an automation action targets a pane
- **THEN** the action applies to that pane's active local pane-tab session

### Requirement: Shared actions support scriptable layout chaining
The system SHALL expose split, focus, run-command, and send-text actions through shared operations that can be chained by hooks and CLI callers using returned IDs.

#### Scenario: Workspace bootstrap creates targetable split layout
- **WHEN** a workspace-opened hook creates a split layout through shared actions
- **THEN** each create/split response provides IDs that the hook can use for later focus and run-command calls

#### Scenario: Hook runs command in selected split
- **WHEN** a hook focuses or targets a newly created pane and invokes run-command
- **THEN** the command executes in that selected pane's live terminal session

### Requirement: Shared action results describe the affected terminal context
Workspace/session actions SHALL return structured metadata describing the affected workspace, tab, pane stack, pane, and session where those IDs are relevant.

#### Scenario: Focus result returns active terminal IDs
- **WHEN** a focus action changes the focused terminal
- **THEN** the action result includes the focused workspace, tab, pane, and session IDs

#### Scenario: Inert action reports unchanged target explicitly
- **WHEN** an action is valid but does not change focus or layout
- **THEN** the action result still identifies the terminal context that was evaluated or targeted

### Requirement: Pane working directories SHALL persist across restart
The system SHALL treat each pane's latest known working directory as durable session state and SHALL restore each pane-backed terminal session using that pane-specific working directory after app restart.

#### Scenario: Distinct pane directories survive restart
- **WHEN** a user has multiple panes whose latest known working directories differ and OpenMUX saves then restores workspace state
- **THEN** each restored pane launches its shell in its own saved working directory rather than the workspace root or another pane's directory

#### Scenario: Missing cwd update preserves launch directory
- **WHEN** a pane has not reported a newer working directory since session launch
- **THEN** the pane's original session working directory remains the persisted restore directory

### Requirement: Pane creation SHALL inherit the source pane working directory
The system SHALL create related panes, splits, and pane tabs using the latest known working directory of the focused or source pane when a source pane exists.

#### Scenario: Split inherits focused pane cwd
- **WHEN** a user splits a focused pane whose latest known working directory differs from the workspace root
- **THEN** the new split pane launches in the focused pane's latest known working directory

#### Scenario: Pane tab inherits stack source cwd
- **WHEN** a user creates a pane tab in a pane stack
- **THEN** the new pane tab launches in the stack's focused pane working directory

### Requirement: Workspace open actions SHALL resolve missing paths from the configured default root
The system SHALL use the configured workspace default root whenever a workspace-open action is invoked without an explicit path. This applies to first app launch without persisted workspaces, native shell workspace creation, control-plane workspace open requests, and `omux open` with no path.

#### Scenario: First launch uses configured root
- **WHEN** OpenMUX launches without persisted workspace state and the user configured a default workspace root
- **THEN** the initial workspace opens at the configured default root

#### Scenario: Sidebar create uses configured root
- **WHEN** the user creates a workspace from native shell chrome without choosing a path
- **THEN** the new workspace opens at the configured default root

#### Scenario: CLI open without path uses configured root
- **WHEN** the user runs `omux open` without a path
- **THEN** the running app opens a workspace at the configured default root

#### Scenario: Explicit open path wins
- **WHEN** the user runs `omux open ~/repo`
- **THEN** the running app opens a workspace at the explicit path instead of the configured default root

### Requirement: Workspace actions SHALL support keyboard and CLI pane navigation
The system SHALL expose shared actions for cycling pane-local tabs within the focused pane stack and cycling panes within the current workspace tab. These actions SHALL be invokable from native shortcuts, `omux` CLI commands, and the control plane.

#### Scenario: Next pane-local tab cycles within focused stack
- **WHEN** the user invokes next pane-local tab navigation from a focused pane stack with multiple pane-local tabs
- **THEN** focus moves to the next pane-local tab in that stack, wrapping to the first pane-local tab after the last

#### Scenario: Previous pane-local tab cycles within focused stack
- **WHEN** the user invokes previous pane-local tab navigation from a focused pane stack with multiple pane-local tabs
- **THEN** focus moves to the previous pane-local tab in that stack, wrapping to the last pane-local tab before the first

#### Scenario: Next pane cycles in visible layout order
- **WHEN** the user invokes next pane navigation in a workspace tab with multiple visible pane stacks
- **THEN** focus moves to the next visible pane in split-tree order, wrapping to the first visible pane after the last

#### Scenario: Previous pane cycles in visible layout order
- **WHEN** the user invokes previous pane navigation in a workspace tab with multiple visible pane stacks
- **THEN** focus moves to the previous visible pane in split-tree order, wrapping to the last visible pane before the first

#### Scenario: Single target navigation is inert
- **WHEN** the user invokes pane or pane-local tab navigation and there is only one valid target
- **THEN** the active focus remains unchanged and no success-shaped state-change event is emitted

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

