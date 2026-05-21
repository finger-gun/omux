## ADDED Requirements

### Requirement: Runtime power profiles SHALL be repeatable
OpenMUX SHALL document a local macOS runtime power profile that can be run before and after presentation-power changes to compare process CPU, memory, thread count, renderer activity, display-link activity, and process energy impact under the same workspace scenario.

#### Scenario: Baseline captures process resource metrics
- **WHEN** a developer runs the runtime power profile against a launched OpenMUX app process
- **THEN** the profile captures the OpenMUX process identifier, elapsed runtime, CPU percentage, memory footprint or RSS, thread count, and sampled call stacks

#### Scenario: Baseline captures renderer activity
- **WHEN** the sampled OpenMUX process is visually idle with inactive workspaces present
- **THEN** the profile records whether sampled stacks include Metal, Core Animation, IOSurface, renderer, or display-link activity

#### Scenario: Baseline captures process energy
- **WHEN** the host system permits process energy sampling with macOS power tools
- **THEN** the profile captures process-level energy data for OpenMUX over a bounded sampling window

#### Scenario: Restricted tools are handled explicitly
- **WHEN** a measurement command requires elevated permissions or is unavailable on the host system
- **THEN** the profile records the missing measurement and still preserves the remaining comparable metrics

### Requirement: Runtime power profiles SHALL use a representative inactive-workspace scenario
The runtime power profile SHALL exercise a representative workspace layout where only one workspace is visible while at least one inactive workspace contains live terminal sessions.

#### Scenario: Inactive workspace process remains live during measurement
- **WHEN** the profile runs with a command or server process in an inactive workspace
- **THEN** the process remains running while OpenMUX measures visible-idle presentation overhead

#### Scenario: Before and after profiles are comparable
- **WHEN** a developer compares profiles from before and after a runtime presentation optimization
- **THEN** both profiles use the same workspace count, pane count, visible workspace, inactive workspace commands, sample duration, and measurement commands unless the deviation is recorded

### Requirement: Runtime power improvements SHALL be validated against correctness
Runtime power validation SHALL pair resource measurements with correctness checks that confirm inactive terminal sessions continue to produce and preserve output.

#### Scenario: Hidden output is preserved
- **WHEN** an inactive workspace terminal writes output while its surface is not user-visible
- **THEN** the output remains available when the workspace becomes visible again

#### Scenario: Lower rendering activity does not imply suspended work
- **WHEN** after-change measurements show reduced renderer or display-link activity for inactive surfaces
- **THEN** the validation also confirms inactive workspace child processes were not paused, killed, or disconnected
