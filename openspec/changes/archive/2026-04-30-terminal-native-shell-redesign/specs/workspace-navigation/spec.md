## ADDED Requirements

### Requirement: Sidebar provides persistent workspace and session orientation
The workspace shell SHALL provide a persistent navigation surface for workspace and session context. The sidebar MUST allow users to understand what workspace is active and quickly switch to other visible workspace or session targets.

#### Scenario: Viewing available workspaces and sessions
- **WHEN** the user opens a workspace window with multiple workspaces or session groups available
- **THEN** the sidebar shows the active context and available navigation targets in a persistent, scan-friendly layout

### Requirement: Navigation chrome remains visually secondary
Workspace navigation SHALL support orientation without dominating the workspace. Sidebar and top-bar chrome MUST stay visually quieter than the terminal canvas and MUST avoid dense dashboard-style action clusters.

#### Scenario: Comparing navigation chrome and terminal content
- **WHEN** the workspace shell renders global navigation and terminal panes at the same time
- **THEN** the navigation chrome remains subordinate in emphasis to the terminal content area

### Requirement: Top bar exposes current context without toolbar sprawl
The workspace shell SHALL provide a top-level context surface for the active workspace. The top bar MUST communicate the current workspace context and lightweight global actions without becoming a feature-dense toolbar.

#### Scenario: Inspecting the active workspace context
- **WHEN** the user focuses a workspace window
- **THEN** the top bar presents active workspace context and limited global shell actions in a compact, low-noise form
