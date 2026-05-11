## MODIFIED Requirements

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
