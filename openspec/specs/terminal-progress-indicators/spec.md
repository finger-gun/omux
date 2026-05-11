# terminal-progress-indicators Specification

## Purpose
Defines how terminal-native and automation-reported progress/status signals appear as transient pane indicators without changing terminal behavior.

## Requirements
### Requirement: Terminal progress drives pane status indicators
OpenMUX SHALL use terminal-native progress reports as the primary signal for pane working, idle, and error indicators.

#### Scenario: Working progress is shown
- **WHEN** a terminal reports active or indeterminate progress
- **THEN** OpenMUX renders a subtle pulsing status orb for that pane

#### Scenario: Removed progress becomes brief idle
- **WHEN** a terminal reports progress removed or done
- **THEN** OpenMUX renders a blue idle orb briefly and then clears the indicator

#### Scenario: Error progress is shown
- **WHEN** a terminal reports progress error
- **THEN** OpenMUX renders a static red status orb for that pane

### Requirement: Status indicators are transient
OpenMUX SHALL NOT persist pane status indicators as durable workspace identity.

#### Scenario: Restored workspace has no stale status
- **WHEN** a workspace is restored after app restart
- **THEN** panes do not show stale working, idle, or error progress from the previous run

### Requirement: Status indicators preserve terminal behavior
Pane status indicators SHALL NOT alter terminal keyboard input, IME composition, Option/Alt behavior, dead keys, compose keys, or terminal mouse input.

#### Scenario: Terminal input remains terminal-owned
- **WHEN** a status orb is visible and the focused terminal receives input
- **THEN** OpenMUX forwards input through the existing terminal input pipeline
