# shell-context-menus Specification

## Purpose
TBD - created by archiving change shell-sidebar-navigation-polish. Update Purpose after archive.

## Requirements

### Requirement: Workspace rows expose contextual management actions
The system SHALL provide a native context menu for each workspace row that includes actions for rename, close, close others, close above, close below, and remove custom name when a custom label is present.

#### Scenario: Showing workspace row actions
- **WHEN** the user opens the context menu on a workspace row with a custom label
- **THEN** the menu includes Rename, Close, Close Others, Close Above, Close Below, and Remove Custom Name

#### Scenario: Hiding irrelevant reset action
- **WHEN** the user opens the context menu on a workspace row that is using its generated default label
- **THEN** the menu does not offer Remove Custom Name

### Requirement: Pane-tab surfaces expose local context actions
The system SHALL provide a native context menu for each pane-tab surface with rename and close-oriented actions whose ordering semantics apply to the pane tabs in that pane stack.

#### Scenario: Showing pane-tab actions
- **WHEN** the user opens the context menu on a pane tab
- **THEN** the menu includes Rename, Close, Close Others, Close Above, and Close Below for that pane stack

#### Scenario: Preserving existing shortcuts
- **WHEN** the user invokes keyboard shortcuts for existing pane or workspace actions
- **THEN** the shortcuts continue to work without requiring the new context menus
