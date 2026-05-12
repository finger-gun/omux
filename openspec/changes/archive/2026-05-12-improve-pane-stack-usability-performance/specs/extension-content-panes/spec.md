## MODIFIED Requirements

### Requirement: Extension panes SHALL participate in workspace layout
The system SHALL allow extension panes to appear inside workspace tabs, split-tree leaves, and pane-local tab stacks using the same OpenMUX pane identifiers and focus model as terminal panes.

#### Scenario: Extension pane opens beside terminal editor
- **WHEN** a caller requests an extension pane split from a focused terminal pane
- **THEN** the workspace layout contains the original terminal pane and the new extension pane as visible split content

#### Scenario: Extension pane can be focused
- **WHEN** a user or control-plane action focuses an extension pane
- **THEN** the workspace focus model records that pane as the focused pane without resolving a terminal session target

#### Scenario: Identity-stable extension pane keeps host continuity during shell updates
- **WHEN** an extension pane remains in the same pane identity while non-structural workspace updates occur
- **THEN** OpenMUX preserves host continuity for that pane instead of replacing its host view instance

