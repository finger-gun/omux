# pane-chrome-identity Specification

## Purpose
TBD - created by archiving change shell-sidebar-navigation-polish. Update Purpose after archive.
## Requirements
### Requirement: Pane chrome avoids redundant identity rows
The system SHALL avoid rendering a persistent pane status row when the only available status text is the current working directory and that information is already represented by the pane title or sidebar metadata.

#### Scenario: Suppressing cwd-only duplication
- **WHEN** a pane has a title that already identifies the terminal and its only status text is the current working directory
- **THEN** the pane does not render an additional persistent cwd-only status row

### Requirement: Pane chrome preserves transient terminal status
The system SHALL continue to render transient terminal status information in pane chrome when that information communicates progress, exit status, renderer health, or other non-identity state.

#### Scenario: Showing active progress state
- **WHEN** a pane reports active terminal progress
- **THEN** the pane chrome renders a status row describing that progress

#### Scenario: Showing exit state
- **WHEN** a pane reports that the command exited with a nonzero code
- **THEN** the pane chrome renders a status row showing the exit state

### Requirement: Pane chrome SHALL keep pane-tab controls attached to tab identity
Pane chrome SHALL present pane-local tab create and close controls as part of the pane-tab strip rather than as a separate trailing control group when those controls operate on pane-local tabs.

#### Scenario: Pane-tab controls are visually scoped to pane tabs
- **WHEN** a pane header renders local pane tabs and pane-tab controls
- **THEN** the add control and per-tab close controls appear within the tab strip so their scope is visually tied to local pane tabs

#### Scenario: Pane header avoids duplicate close affordance for focused local tab
- **WHEN** per-tab close controls are rendered for closable local pane tabs
- **THEN** the pane header does not also render a separate generic close-focused-pane-tab button for the same operation

