## ADDED Requirements

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
