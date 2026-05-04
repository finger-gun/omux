## MODIFIED Requirements

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
