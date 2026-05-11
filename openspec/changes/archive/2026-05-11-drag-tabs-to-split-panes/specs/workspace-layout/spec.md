## ADDED Requirements

### Requirement: Workspace layout SHALL support directional pane-tab drag splits
The system SHALL allow workspace split-tree changes to be initiated by dropping a dragged pane-local tab onto a valid pane stack with a resolved direction of left, right, up, or down.

#### Scenario: Directional drop updates split tree
- **WHEN** a dragged pane-local tab is dropped onto a valid target pane stack with a resolved split direction
- **THEN** the workspace split tree SHALL insert a new pane stack on the requested side of the target pane stack

#### Scenario: Direction maps to split axis
- **WHEN** a drag-to-split drop resolves to left or right
- **THEN** OpenMUX SHALL use a column split, and when it resolves to up or down OpenMUX SHALL use a row split

#### Scenario: Drag split uses OpenMUX layout model
- **WHEN** a drag-to-split drop changes workspace structure
- **THEN** the resulting state SHALL be represented by OpenMUX workspace layout nodes rather than terminal-engine layout internals
