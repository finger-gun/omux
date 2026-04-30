## ADDED Requirements

### Requirement: Terminal remains the dominant workspace surface
The macOS workspace shell SHALL present terminal panes as the primary working surface. Shell chrome MUST provide orientation and focus support without visually overpowering the terminal canvas or making terminals feel subordinate to application panels.

#### Scenario: Rendering a workspace with navigation chrome
- **WHEN** a workspace window renders sidebar, top-bar, and pane content together
- **THEN** the shell presents the terminal canvas as the visually dominant area and uses navigation chrome as secondary support

### Requirement: Shell behavior remains terminal-native
The shell SHALL preserve a terminal-native experience that feels open, flexible, and workflow-agnostic. The product MUST NOT require editor-style side panels, browser surfaces, or workflow-specific dashboards to perform primary terminal work.

#### Scenario: User works across multiple panes and sessions
- **WHEN** the user switches between workspaces, sessions, splits, or pane-local tabs
- **THEN** the shell supports those transitions without requiring non-terminal surfaces to become the main interaction model

### Requirement: Shell composition stays separate from terminal hosting
The shell SHALL implement its visual hierarchy in app-shell presentation layers and MUST keep terminal-hosting concerns behind the existing terminal bridge boundary.

#### Scenario: Applying shell redesign changes
- **WHEN** the redesign introduces new shell views, pane chrome, or theme styling
- **THEN** those changes keep libghostty-specific and terminal runtime implementation details isolated behind the terminal bridge
