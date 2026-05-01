## ADDED Requirements

### Requirement: The native shell SHALL minimize non-terminal chrome
The native macOS shell SHALL prioritize pane space over decorative chrome by removing low-value persistent header UI and reducing nested card-like container treatment around terminal content. Pane-local headers MAY remain where needed for pane-tab navigation and pane context.

#### Scenario: Shell does not reserve a top header row
- **WHEN** a workspace window is shown
- **THEN** the main content region does not include the current persistent top header bar and that vertical space is available to pane content

#### Scenario: Pane content is not wrapped in stacked cards
- **WHEN** a terminal pane stack is rendered
- **THEN** the shell avoids multiple nested rounded bordered containers around the pane and keeps the pane header as the primary remaining pane-local chrome

### Requirement: The native shell SHALL support a collapsible workspace column
The native macOS shell SHALL allow the workspace navigation column to be shown or hidden at runtime without changing workspace model data, SHALL persist that visibility state across app restarts as OpenMUX-owned UI state, and SHALL expand the pane content area when the column is hidden.

#### Scenario: Hiding the workspace column expands pane space
- **WHEN** the user triggers the workspace-column toggle while a workspace window is focused
- **THEN** the workspace column collapses and the main pane region expands to use the reclaimed width

#### Scenario: Showing the workspace column restores navigation UI
- **WHEN** the user triggers the workspace-column toggle again
- **THEN** the workspace column becomes visible again without recreating the workspace model

#### Scenario: Sidebar visibility survives restart
- **WHEN** the user closes OpenMUX after hiding or showing the workspace column and later launches OpenMUX again
- **THEN** the workspace column visibility matches the last remembered OpenMUX UI state

### Requirement: The native shell SHALL visually integrate the titlebar with the shell
The native macOS shell SHALL use AppKit window configuration so the titlebar/background region visually blends with the shell instead of appearing as a separate contrasting strip above the workspace content.

#### Scenario: Window chrome reads as one shell surface
- **WHEN** a workspace window is displayed with the current theme
- **THEN** the titlebar region visually matches or blends with the shell background rather than presenting a separate default macOS band
