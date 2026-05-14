# workspace-layout Specification

## Purpose
TBD - created by archiving change workspace-shell. Update Purpose after archive.
## Requirements
### Requirement: The shell SHALL support tabs and split panes
The system SHALL provide native workspace layout behavior for top-level workspace tabs, nested split panes, and pane-local tab stacks in the AppKit shell.

#### Scenario: User creates another pane in the workspace
- **WHEN** a workspace action requests a split
- **THEN** the shell creates another split region from the active local pane tab within the current workspace layout

### Requirement: The shell SHALL maintain explicit pane and tab focus
The system SHALL maintain explicit focus state for the active top-level workspace tab, focused pane stack, and active local pane tab within a workspace.

#### Scenario: Focus follows workspace navigation
- **WHEN** the user or control plane focuses another pane stack, local pane tab, or top-level tab
- **THEN** the shell updates the active workspace focus model to match that selection

### Requirement: Workspace layout SHALL use OpenMUX-native concepts
The system SHALL represent top-level tabs, pane stacks, local pane tabs, split-tree structure, and focus behavior using OpenMUX workspace abstractions instead of terminal-engine-specific layout state.

#### Scenario: Layout changes remain app-level behavior
- **WHEN** a top-level tab, local tab, or split-pane action changes workspace structure
- **THEN** the resulting state is represented by OpenMUX-native workspace models rather than terminal-engine layout internals

### Requirement: Workspace layout SHALL support non-terminal pane content
Workspace layout SHALL allow split-tree leaves and pane-local tab stacks to contain panes whose content is not backed by a terminal session.

#### Scenario: Split layout contains terminal and extension panes
- **WHEN** an extension pane is created beside a terminal pane
- **THEN** the workspace split tree preserves both panes in the same layout model without requiring the extension pane to own a terminal session

#### Scenario: Pane-local stack contains extension pane
- **WHEN** an extension pane is added to a pane-local tab stack
- **THEN** the stack can focus that pane while preserving sibling terminal panes in the same stack

### Requirement: Workspace layout operations SHALL preserve terminal-only target resolution
Workspace layout SHALL distinguish pane focus from terminal target resolution so actions that require a live terminal session fail explicitly when aimed at extension panes.

#### Scenario: Run command rejects extension pane target
- **WHEN** a caller targets an extension pane with a command-running action
- **THEN** OpenMUX returns a structured failure instead of silently choosing another terminal

#### Scenario: Split from extension pane is valid
- **WHEN** a caller requests a layout split from a focused extension pane
- **THEN** OpenMUX creates a new pane in the requested split location without needing terminal session state from the source pane

#### Scenario: Split pane containing extension content can be closed
- **WHEN** a workspace contains terminal and extension panes in separate split-tree leaves
- **THEN** pane close actions can remove either split pane and collapse the remaining layout without requiring pane-local tab siblings

### Requirement: Workspace layout SHALL support directional pane-tab drag splits
The system SHALL allow workspace split-tree changes to be initiated by dropping a dragged pane-local tab onto a valid pane stack with a resolved direction of left, right, up, or down.

#### Scenario: Directional drop updates split tree
- **WHEN** a dragged pane-local tab is dropped onto a valid target pane stack with a resolved split direction
- **THEN** the workspace split tree SHALL insert a new pane stack on the requested side of the target pane stack

#### Scenario: Direction maps to split axis
- **WHEN** a drag-to-split drop resolves to left or right
- **THEN** OpenMUX SHALL use a column split, and when it resolves to up or down OpenMUX SHALL use a row split

#### Scenario: Drag split uses OpenMUX layout model
- **WHEN** a drag-to-split drop changes workspace structure
- **THEN** the resulting state SHALL be represented by OpenMUX workspace layout nodes rather than terminal-engine layout internals

### Requirement: Workspace layout SHALL track floating pane modal presentation
The workspace model SHALL represent floating pane modal presentation as OpenMUX-owned workspace state separate from the docked split tree while preserving the same pane and pane-stack abstractions.

#### Scenario: Workspace contains docked and floating pane content
- **WHEN** a workspace has docked pane stacks and one or more floating pane modals
- **THEN** OpenMUX represents both through workspace-owned layout state rather than terminal-runtime layout internals

#### Scenario: Floating pane does not require terminal session retargeting
- **WHEN** a pane moves from docked presentation to floating modal presentation
- **THEN** OpenMUX updates workspace presentation state without requiring a new terminal target resolution model for that pane

### Requirement: Workspace layout transitions SHALL support dock and undock operations
The system SHALL support moving a pane between docked pane-stack layout and floating modal presentation while preserving focus and normal layout normalization rules.

#### Scenario: Undocking last tab collapses empty source stack
- **WHEN** the user moves the only pane tab from a docked source stack into a floating modal
- **THEN** OpenMUX collapses the empty source stack using normal layout normalization

#### Scenario: Docking modal pane into target stack focuses moved pane
- **WHEN** a floating modal pane is docked into a valid target pane stack
- **THEN** OpenMUX inserts that pane into the target stack and focuses the moved pane there
