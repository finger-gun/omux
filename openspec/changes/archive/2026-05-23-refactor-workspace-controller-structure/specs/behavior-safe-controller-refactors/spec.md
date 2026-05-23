## ADDED Requirements

### Requirement: Controller refactor slices SHALL preserve existing behavior
Each controller refactor slice SHALL prove behavioral parity with pre-refactor behavior for workspace, pane, tab, and terminal-target flows.

#### Scenario: Existing controller flows remain semantically equivalent
- **WHEN** refactored code handles create/focus/split/close/restore operations
- **THEN** observable outputs and state transitions match baseline behavior

#### Scenario: Event and hook payload compatibility remains intact
- **WHEN** refactored code emits lifecycle/session/control-plane events
- **THEN** payload shape and required fields remain backward-compatible

#### Scenario: Publication ordering remains compatible
- **WHEN** a refactored controller-owned action emits both a hook invocation and a control-plane event
- **THEN** the observable publication ordering remains compatible with the pre-refactor behavior for that action
