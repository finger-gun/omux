# sidebar-terminal-metadata Specification

## Purpose
TBD - created by archiving change shell-sidebar-navigation-polish. Update Purpose after archive.
## Requirements
### Requirement: Sidebar lists terminal metadata within each workspace
The system SHALL allow each workspace row to show child terminal metadata rows for the terminals contained in that workspace, using subtle presentation that keeps the workspace row visually primary, and SHALL treat those terminal rows as direct navigation targets.

#### Scenario: Rendering terminal metadata rows
- **WHEN** a workspace contains multiple terminals with distinct current locations
- **THEN** the sidebar shows multiple child rows beneath that workspace rather than collapsing all metadata into a single line

#### Scenario: Navigating through terminal metadata rows
- **WHEN** the user selects a terminal metadata row in the sidebar
- **THEN** the corresponding terminal becomes focused in its workspace

#### Scenario: Navigating to terminal row in inactive workspace
- **WHEN** the user selects a terminal metadata row under a workspace that is not currently active
- **THEN** OpenMUX makes that workspace active and focuses the selected terminal

### Requirement: Terminal metadata uses repo, branch, and path when available
The system SHALL derive terminal metadata from OpenMUX-owned shell state, preferring repository and branch information when available and falling back to path-only display when repository information cannot be resolved.

#### Scenario: Showing git-aware metadata
- **WHEN** a terminal reports a working directory inside a git repository on branch `main`
- **THEN** the sidebar metadata for that terminal includes `main` and the terminal path

#### Scenario: Falling back outside a repository
- **WHEN** a terminal reports a working directory that is not inside a git repository
- **THEN** the sidebar metadata for that terminal shows the path without requiring repository or branch data

### Requirement: Git metadata resolution avoids persistent background services
The system SHALL resolve repository metadata on demand from workspace or pane paths and SHALL NOT require a continuously running background indexing service to keep sidebar metadata current.

#### Scenario: Refreshing after cwd change
- **WHEN** a pane reports a new working directory through terminal dispatch
- **THEN** OpenMUX refreshes that terminal's sidebar metadata using on-demand repository inspection

