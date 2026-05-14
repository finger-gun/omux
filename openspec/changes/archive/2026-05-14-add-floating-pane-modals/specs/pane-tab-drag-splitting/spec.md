## ADDED Requirements

### Requirement: Pane-tab drag SHALL support tear-out to floating modal presentation
The system SHALL allow an eligible pane tab drag to resolve to floating modal presentation when the user drops it in a valid tear-out zone outside docked merge and split targets.

#### Scenario: Dragging docked tab to tear-out zone creates modal
- **WHEN** the user drags an eligible pane tab to a valid tear-out zone and releases it
- **THEN** OpenMUX moves that pane into a floating modal and focuses the moved pane there

#### Scenario: Tear-out preserves pane identity
- **WHEN** a pane tab is moved from a docked pane stack into a floating modal by drag
- **THEN** OpenMUX preserves the pane ID, title, plugin ownership, and associated host state for the moved pane

### Requirement: Pane-tab drag SHALL support docking floating pane content back into pane stacks
The system SHALL allow a floating modal pane tab or modal header drag to dock that pane into a valid workspace pane-stack target using defined drop semantics.

#### Scenario: Dropping modal pane on pane tab strip docks into stack
- **WHEN** the user drags a floating modal pane onto the tab strip of a docked pane stack
- **THEN** OpenMUX docks the pane into that stack and focuses it in the target stack

#### Scenario: Invalid dock target is inert
- **WHEN** the user drops a floating modal pane outside a valid dock target
- **THEN** OpenMUX leaves the pane in its floating modal and keeps workspace layout unchanged
