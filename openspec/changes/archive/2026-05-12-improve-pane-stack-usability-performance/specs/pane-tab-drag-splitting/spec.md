## MODIFIED Requirements

### Requirement: Dragging onto another pane tab strip SHALL merge the tab into that stack
The system SHALL recognize pane-tab header drops for both different-stack merge and same-stack reorder, while preserving directional split behavior outside header regions.

#### Scenario: Hover over a different pane tab strip shows merge preview
- **WHEN** the user drags a pane tab over the tab strip region of a different pane stack
- **THEN** OpenMUX SHALL highlight the full width of that tab strip to indicate the tab will be appended to that stack

#### Scenario: Merge preview takes priority over edge-split preview
- **WHEN** the cursor is in the tab strip zone of a different pane stack
- **THEN** OpenMUX SHALL resolve the intent as merge rather than directional split

#### Scenario: Dropping on another pane tab strip appends tab to that stack
- **WHEN** the user drops a dragged pane tab while the merge preview is visible
- **THEN** OpenMUX SHALL move the pane tab into the target pane stack, appending it after its existing tabs

#### Scenario: Merged tab becomes focused in its new stack
- **WHEN** a pane tab is successfully merged into a different pane stack
- **THEN** OpenMUX SHALL focus the merged pane tab in the target pane stack

#### Scenario: Merge drop from a single-tab source collapses the source stack
- **WHEN** the user drags the only pane tab from its source stack and merges it into a different pane stack
- **THEN** OpenMUX SHALL collapse the empty source stack using normal split-tree layout normalization

#### Scenario: Merge drop preserves terminal session identity
- **WHEN** a pane tab is moved into a different stack by drag-to-merge
- **THEN** OpenMUX SHALL preserve the pane ID, session ID, terminal surface association, title, and terminal state for the merged pane tab

#### Scenario: Dropping in the source pane tab strip reorders within the same stack
- **WHEN** the user drags a pane tab and drops it in the tab strip of its source pane stack
- **THEN** OpenMUX SHALL reorder pane tabs within that same stack according to drop position and keep the moved tab focused

