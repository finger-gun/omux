## ADDED Requirements

### Requirement: Pane-local tabs SHALL move into newly split stacks
The system SHALL support moving an existing pane-local tab from one pane stack into a newly created pane stack adjacent to a valid target pane stack.

#### Scenario: Pane tab moves out of source stack
- **WHEN** a pane-local tab is successfully dropped onto a valid drag-to-split target
- **THEN** OpenMUX SHALL remove that pane tab from its source stack and place it as the focused tab in the newly created target-adjacent pane stack

#### Scenario: Source stack focus remains valid after move
- **WHEN** a pane-local tab is moved out of a source stack that still contains other pane tabs
- **THEN** OpenMUX SHALL keep or assign a valid focused pane tab in the source stack

#### Scenario: Empty source stack collapses
- **WHEN** a pane-local tab is moved out of a source stack that has no remaining pane tabs
- **THEN** OpenMUX SHALL remove the empty source stack and normalize the split tree

#### Scenario: Same-stack drop is rejected
- **WHEN** a pane-local tab is dropped onto its own source pane stack
- **THEN** OpenMUX SHALL leave the pane tab in its original stack and SHALL NOT create a new split
