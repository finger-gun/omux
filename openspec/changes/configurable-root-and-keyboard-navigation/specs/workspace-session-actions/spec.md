## ADDED Requirements

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
