## ADDED Requirements

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
