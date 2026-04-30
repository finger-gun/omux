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
The system SHALL track the active local pane tab within each pane stack independently of the focused top-level workspace tab and focused pane stack.

#### Scenario: Focusing a local tab preserves workspace-level context
- **WHEN** a user focuses another local tab inside the same split region
- **THEN** the workspace tab and pane-stack focus remain stable while the active local pane tab changes

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
