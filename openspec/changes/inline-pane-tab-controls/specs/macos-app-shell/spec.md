## ADDED Requirements

### Requirement: Native shell SHALL route inline pane-tab controls through shared pane-stack actions
The native macOS shell SHALL implement inline pane-tab add and close controls as AppKit-owned shell chrome that calls the existing shared pane-stack actions without involving terminal-engine internals.

#### Scenario: Inline controls preserve the terminal bridge boundary
- **WHEN** the user creates or closes a pane-local tab through inline pane-tab chrome
- **THEN** the native shell routes the action through OpenMUX workspace/controller operations without requiring `libghostty` types outside the terminal bridge

#### Scenario: Inline controls do not alter terminal keyboard ownership
- **WHEN** inline pane-tab controls are added to pane chrome
- **THEN** terminal keyboard input, IME composition, Option/right-Option input, and unrelated terminal pointer regions remain terminal-owned
