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

### Requirement: Pane chrome SHALL render drag split feedback without obscuring identity
Pane chrome SHALL provide pane-tab drag affordance and directional split-preview feedback while preserving clear pane-tab identity, close/create controls, and terminal status chrome.

#### Scenario: Drag affordance remains scoped to pane tab
- **WHEN** a pane-local tab is draggable
- **THEN** its drag affordance SHALL be visually and interactively scoped to that pane tab rather than to unrelated pane header controls

#### Scenario: Split preview does not replace pane identity
- **WHEN** a pane-tab drag preview is visible over a pane stack
- **THEN** OpenMUX SHALL continue rendering pane tab identity and terminal status chrome without replacing them with persistent drag state

#### Scenario: Split preview is transient
- **WHEN** a pane-tab drag is cancelled or completed
- **THEN** OpenMUX SHALL remove the split preview highlight

#### Scenario: Drag ghost is visually distinct from split preview
- **WHEN** both the drag ghost and a directional split preview are visible simultaneously
- **THEN** the floating tab ghost and the target split-preview highlight SHALL be visually distinguishable so the user can read both signals without confusion

#### Scenario: Merge preview highlights only the target tab strip
- **WHEN** the drag ghost hovers over the tab strip of a different pane stack and the merge intent is resolved
- **THEN** OpenMUX SHALL render a full-width highlight over that pane stack's tab strip only, without obscuring pane content or terminal chrome

### Requirement: Pane chrome separates identity from operational status
Pane chrome SHALL preserve pane identity while rendering transient operational status as compact chrome.

#### Scenario: Status orb appears before semantic icon
- **WHEN** a pane has active progress/status and is shown in the workspace pane list
- **THEN** the pane row renders a small status orb before the semantic icon and title

#### Scenario: Pane tab shows same status language
- **WHEN** a pane tab has active progress/status
- **THEN** the pane tab renders the same status orb before the tab name and semantic icon

#### Scenario: Status does not replace identity
- **WHEN** a pane has progress/status metadata
- **THEN** pane title, semantic icon, and cwd-derived identity remain available and are not replaced by status text

### Requirement: Pane status avoids cwd-only duplication
Pane chrome SHALL continue to avoid redundant cwd-only status rows when rendering progress/status indicators.

#### Scenario: Cwd-only status remains suppressed
- **WHEN** a pane has no transient progress/status beyond current working directory identity
- **THEN** pane chrome does not render a persistent cwd-only status row
