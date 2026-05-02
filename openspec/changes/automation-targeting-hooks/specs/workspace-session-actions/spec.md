## ADDED Requirements

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
