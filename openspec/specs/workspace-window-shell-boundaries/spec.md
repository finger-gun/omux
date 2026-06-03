# workspace-window-shell-boundaries Specification

## Purpose
TBD - created by archiving change refactor-workspace-controller-structure. Update Purpose after archive.
## Requirements
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

### Requirement: Shell UI primitives SHALL be organized into dedicated files within `OmuxAppShell`
Shared UI components extracted from `WorkspaceWindowController.swift` SHALL each live in their own Swift source file under `Sources/OmuxAppShell/`, consistent with the module boundary requirement that shell concerns are partitioned rather than concentrated in one file.

#### Scenario: Extracted components are in dedicated files
- **WHEN** a developer navigates the `Sources/OmuxAppShell/` directory
- **THEN** `SidebarContainerView.swift`, `CollapsibleSectionHeaderView.swift`, and `CountBadgeView.swift` exist as distinct files, separate from `WorkspaceWindowController.swift`

#### Scenario: WorkspaceWindowController.swift no longer contains extracted type definitions
- **WHEN** `WorkspaceWindowController.swift` is inspected after extraction
- **THEN** the type definitions for `SidebarContainerView`, `CollapsibleSectionHeaderView`, and `CountBadgeView` are absent from that file

