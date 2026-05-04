## ADDED Requirements

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
