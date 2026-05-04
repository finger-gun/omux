## MODIFIED Requirements

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
