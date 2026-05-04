## ADDED Requirements

### Requirement: Pane-local tab commands SHALL be keyboard accessible
The system SHALL expose native key commands for creating, closing, and cycling pane-local tabs in the focused pane stack.

#### Scenario: Create pane-local tab shortcut
- **WHEN** a terminal pane is focused and the user presses `Cmd+T`
- **THEN** OpenMUX creates a new pane-local tab in the focused pane stack

#### Scenario: Close pane-local tab shortcut
- **WHEN** a terminal pane is focused in a pane stack with more than one pane-local tab and the user presses `Cmd+W`
- **THEN** OpenMUX closes the focused pane-local tab

#### Scenario: Close last pane-local tab is rejected
- **WHEN** a terminal pane is focused in a pane stack with only one pane-local tab and the user presses `Cmd+W`
- **THEN** OpenMUX leaves the pane stack unchanged

#### Scenario: Cycle pane-local tab shortcut
- **WHEN** a terminal pane is focused in a pane stack with more than one pane-local tab and the user presses `Ctrl+Tab`
- **THEN** OpenMUX focuses the next pane-local tab in that pane stack

### Requirement: Pane-local tab navigation SHALL be available to automation
The system SHALL expose next and previous pane-local tab focus operations through the same shared action model used by native shell interactions and `omux`.

#### Scenario: CLI focuses next pane-local tab
- **WHEN** a user or hook invokes `omux pane-tab-next`
- **THEN** OpenMUX focuses the next pane-local tab in the focused pane stack

#### Scenario: CLI focuses previous pane-local tab
- **WHEN** a user or hook invokes `omux pane-tab-prev`
- **THEN** OpenMUX focuses the previous pane-local tab in the focused pane stack
