# workspace-render-reconciliation Specification

## Purpose
TBD - created by archiving change improve-pane-stack-usability-performance. Update Purpose after archive.
## Requirements
### Requirement: Workspace canvas updates SHALL reconcile by stable identity
The shell SHALL reconcile workspace canvas updates using stable OpenMUX identifiers so unchanged pane stacks and pane hosts are reused instead of always being destroyed and recreated.

#### Scenario: Non-structural update reuses pane host views
- **WHEN** workspace state changes only in pane metadata or extension content while pane-stack and pane identities remain unchanged
- **THEN** OpenMUX reuses existing hosted pane views for those identities and does not rebuild the entire canvas subtree

#### Scenario: Structural update replaces only affected subtree
- **WHEN** a split topology or pane-stack membership change occurs
- **THEN** OpenMUX updates only the affected layout subtree and preserves unaffected identity-matched subtrees

### Requirement: Reconciled updates SHALL preserve interactive view state
For identity-stable panes, reconciled updates SHALL preserve responder/focus continuity and extension-pane runtime host state needed for interactive reading and editing workflows.

#### Scenario: Terminal focus survives status/content update
- **WHEN** a focused terminal pane receives non-structural workspace updates
- **THEN** the terminal pane remains the active input target after reconciliation

#### Scenario: Extension pane state survives non-structural update
- **WHEN** an extension pane remains identity-stable across a non-structural update
- **THEN** its host view state required for continuity (including scroll position) remains preserved

### Requirement: Reconciliation SHALL remain shell-owned and bridge-safe
Reconciliation behavior SHALL remain in app-shell workspace rendering and SHALL NOT require terminal-engine layout ownership or libghostty type exposure outside `OmuxTerminalBridge`.

#### Scenario: Reconciliation does not mutate terminal bridge layout ownership
- **WHEN** OpenMUX applies a reconciled workspace render update
- **THEN** it uses OpenMUX workspace/pane identifiers and shell-owned view orchestration without introducing terminal-engine layout APIs into shell modules

