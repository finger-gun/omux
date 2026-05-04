# pane-tab-stacks Specification

## Purpose
TBD - created by archiving change pane-tab-stacks. Update Purpose after archive.
## Requirements
### Requirement: Split-tree leaves SHALL host pane-local tab stacks
The system SHALL model each split-tree leaf as a pane-local tab stack that can hold one or more local pane tabs while exposing one active local pane tab at a time.

#### Scenario: Split region contains multiple local tabs
- **WHEN** a user creates a local tab inside a split region
- **THEN** the split region keeps its position in the layout and switches between local pane tabs within that region

### Requirement: Pane stacks SHALL maintain explicit local tab focus
The system SHALL track the active local pane tab within each pane stack independently of the focused top-level workspace tab and focused pane stack, and SHALL allow direct focus of a pane tab by pane ID from any visible workspace.

#### Scenario: Focusing a local tab preserves workspace-level context
- **WHEN** a user focuses another local tab inside the same split region
- **THEN** the workspace tab and pane-stack focus remain stable while the active local pane tab changes

#### Scenario: Sidebar focuses pane tab in inactive workspace
- **WHEN** the user selects a visible sidebar terminal row for a pane tab in an inactive workspace
- **THEN** OpenMUX activates that workspace and focuses the selected pane tab

#### Scenario: Missing pane tab focus is inert
- **WHEN** a pane-tab focus request targets a pane ID that does not exist
- **THEN** the active workspace and focused pane tab remain unchanged

### Requirement: Splitting SHALL operate on the active local pane tab
The system SHALL split the active local pane tab inside the focused pane stack when a split-right or split-down action is requested.

#### Scenario: Split down then split right inside the lower region
- **WHEN** a user splits a pane down and then splits the active lower local pane tab to the right
- **THEN** the resulting layout preserves the top region while only the lower region becomes a nested horizontal split

### Requirement: Pane-stack actions SHALL be shared by UI and automation
The system SHALL expose pane-stack-local tab creation, focus, and close actions through shared OpenMUX operations that can be invoked by both the native shell and `omux`.

#### Scenario: Local tab action is available through the control plane
- **WHEN** a user or tool creates or focuses a local pane tab
- **THEN** the action operates through the same pane-stack contract used by the native shell

### Requirement: Pane-local tab commands SHALL be keyboard accessible
The system SHALL expose native key commands for creating, closing, and cycling pane-local tabs in the focused pane stack.

#### Scenario: Create pane-local tab shortcut
- **WHEN** a terminal pane is focused and the user presses `Cmd+T`
- **THEN** OpenMUX creates a new pane-local tab in the focused pane stack

#### Scenario: Close pane-local tab shortcut
- **WHEN** a terminal pane is focused in a pane stack with more than one pane-local tab and the user presses `Cmd+W`
- **THEN** OpenMUX closes the focused pane-local tab

#### Scenario: Close last pane-local tab is rejected
- **WHEN** a terminal pane is focused in a pane stack with only one pane-local tab and the user presses `Cmd+W`
- **THEN** OpenMUX leaves the pane stack unchanged

#### Scenario: Cycle pane-local tab shortcut
- **WHEN** a terminal pane is focused in a pane stack with more than one pane-local tab and the user presses `Ctrl+Tab`
- **THEN** OpenMUX focuses the next pane-local tab in that pane stack

### Requirement: Pane-local tab navigation SHALL be available to automation
The system SHALL expose next and previous pane-local tab focus operations through the same shared action model used by native shell interactions and `omux`.

#### Scenario: CLI focuses next pane-local tab
- **WHEN** a user or hook invokes `omux pane-tab-next`
- **THEN** OpenMUX focuses the next pane-local tab in the focused pane stack

#### Scenario: CLI focuses previous pane-local tab
- **WHEN** a user or hook invokes `omux pane-tab-prev`
- **THEN** OpenMUX focuses the previous pane-local tab in the focused pane stack

### Requirement: Pane-stack tab strips SHALL expose inline creation
Pane-local tab stacks SHALL render their local tab creation affordance directly in the pane-stack tab strip immediately after the last local pane tab.

#### Scenario: Add control follows last local tab
- **WHEN** a pane stack with one or more local pane tabs is rendered
- **THEN** the add-pane-tab control appears in the same strip immediately after the last local pane tab

#### Scenario: Inline add creates a local pane tab in the same stack
- **WHEN** the user activates the inline add-pane-tab control for a pane stack
- **THEN** the system creates a new local pane tab in that pane stack using the shared pane-stack create action

### Requirement: Pane-stack tab strips SHALL expose per-tab close controls
Pane-local tab stacks SHALL provide a close affordance on each closable local pane tab that closes that specific pane tab through the shared pane-stack close action.

#### Scenario: Close control targets its own tab
- **WHEN** the user activates the close control on a local pane tab
- **THEN** the system closes that specific local pane tab without closing a different focused local pane tab

#### Scenario: Single local tab is not closable inline
- **WHEN** a pane stack contains only one local pane tab
- **THEN** the tab strip does not expose an enabled close affordance for that tab

