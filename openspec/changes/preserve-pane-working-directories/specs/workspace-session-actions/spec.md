## ADDED Requirements

### Requirement: Pane working directories SHALL persist across restart
The system SHALL treat each pane's latest known working directory as durable session state and SHALL restore each pane-backed terminal session using that pane-specific working directory after app restart.

#### Scenario: Distinct pane directories survive restart
- **WHEN** a user has multiple panes whose latest known working directories differ and OpenMUX saves then restores workspace state
- **THEN** each restored pane launches its shell in its own saved working directory rather than the workspace root or another pane's directory

#### Scenario: Missing cwd update preserves launch directory
- **WHEN** a pane has not reported a newer working directory since session launch
- **THEN** the pane's original session working directory remains the persisted restore directory

### Requirement: Pane creation SHALL inherit the source pane working directory
The system SHALL create related panes, splits, and pane tabs using the latest known working directory of the focused or source pane when a source pane exists.

#### Scenario: Split inherits focused pane cwd
- **WHEN** a user splits a focused pane whose latest known working directory differs from the workspace root
- **THEN** the new split pane launches in the focused pane's latest known working directory

#### Scenario: Pane tab inherits stack source cwd
- **WHEN** a user creates a pane tab in a pane stack
- **THEN** the new pane tab launches in the stack's focused pane working directory
