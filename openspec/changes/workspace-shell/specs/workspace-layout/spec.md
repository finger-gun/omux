## ADDED Requirements

### Requirement: The shell SHALL support tabs and split panes
The system SHALL provide native workspace layout behavior for tabs and split panes in the AppKit shell.

#### Scenario: User creates another pane in the workspace
- **WHEN** a workspace action requests a split
- **THEN** the shell creates another pane within the current workspace layout

### Requirement: The shell SHALL maintain explicit pane and tab focus
The system SHALL maintain explicit focus state for the active tab and pane within a workspace.

#### Scenario: Focus follows workspace navigation
- **WHEN** the user or control plane focuses another pane or tab
- **THEN** the shell updates the active workspace focus model to match that selection

### Requirement: Workspace layout SHALL use OpenMUX-native concepts
The system SHALL represent tab, pane, and focus behavior using OpenMUX workspace abstractions instead of terminal-engine-specific layout state.

#### Scenario: Layout changes remain app-level behavior
- **WHEN** a tab or split-pane action changes workspace structure
- **THEN** the resulting state is represented by OpenMUX-native workspace and pane models
