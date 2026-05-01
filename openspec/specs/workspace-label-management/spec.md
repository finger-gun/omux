# workspace-label-management Specification

## Purpose
TBD - created by archiving change shell-sidebar-navigation-polish. Update Purpose after archive.

## Requirements

### Requirement: Workspace labels use generated defaults
The system SHALL assign each new workspace a generated default label in the form `Workspace N`, where `N` is the lowest positive integer not currently in use by another generated workspace label.

#### Scenario: Opening the first workspace
- **WHEN** the user opens a workspace and no generated workspace labels are in use
- **THEN** the workspace label is `Workspace 1`

#### Scenario: Filling the next available generated label
- **WHEN** the user opens a new workspace while generated labels `Workspace 1` and `Workspace 3` exist
- **THEN** the new workspace label is `Workspace 2`

### Requirement: Workspace labels support custom overrides and reset
The system SHALL allow a workspace to carry an optional custom label override, SHALL display that override when present, and SHALL provide a reset operation that removes the custom label and restores the generated workspace label.

#### Scenario: Applying a custom workspace name
- **WHEN** the user renames `Workspace 2` to `Client Shell`
- **THEN** the workspace displays `Client Shell` without changing its generated default label assignment

#### Scenario: Removing a custom workspace name
- **WHEN** the user removes a custom label from a workspace whose generated label is `Workspace 2`
- **THEN** the workspace displays `Workspace 2`
