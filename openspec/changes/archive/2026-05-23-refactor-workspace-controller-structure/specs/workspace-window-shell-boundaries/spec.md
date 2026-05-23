## ADDED Requirements

### Requirement: Workspace window shell responsibilities SHALL be modularized by shell concern
Shell-owned workspace window logic SHALL be partitioned into explicit modules for top-level window orchestration, workspace canvas composition, sidebar/floating-modal composition, and pane chrome helpers instead of concentrating those concerns in one oversized `WorkspaceWindowController` file.

#### Scenario: Shell composition uses dedicated modules
- **WHEN** the workspace window renders sidebar, canvas, floating modal, and pane chrome content
- **THEN** those shell concerns are composed through dedicated shell-owned modules rather than one monolithic window-controller file

### Requirement: Shell extraction SHALL preserve AppKit-first and bridge-safe ownership
Refactoring `WorkspaceWindowController` SHALL preserve AppKit-first shell ownership, accessibility behavior, pane identity continuity, and terminal-bridge ownership boundaries.

#### Scenario: Extracted shell modules stay terminal-bridge-safe
- **WHEN** the shell renders or updates terminal-backed panes after extraction
- **THEN** terminal surface ownership remains behind `OmuxTerminalBridge` and extracted shell modules continue to operate on OpenMUX-native pane and workspace identities

#### Scenario: Extracted shell modules preserve interactive shell behavior
- **WHEN** the shell updates sidebar items, pane headers, floating modals, overlays, or pane tabs after extraction
- **THEN** focus behavior, accessibility identifiers, and host continuity remain behaviorally compatible with the pre-refactor shell
