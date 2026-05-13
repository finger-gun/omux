## ADDED Requirements

### Requirement: Workspace controller responsibilities SHALL be modularized by concern
Workspace runtime logic SHALL be partitioned into explicit modules for state/index management, side-effect orchestration, and event publication, each with clear contracts.

#### Scenario: State mutation path uses dedicated state module
- **WHEN** a workspace/pane/tab mutation operation is executed
- **THEN** state updates occur through the state module interface rather than inline controller-wide logic

#### Scenario: Event publication path uses dedicated publisher
- **WHEN** a mutation emits hook or control-plane events
- **THEN** publication occurs through dedicated publisher interfaces with unchanged payload semantics
