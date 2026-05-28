## ADDED Requirements

### Requirement: Shell UI primitives SHALL be organized into dedicated files within `OmuxAppShell`
Shared UI components extracted from `WorkspaceWindowController.swift` SHALL each live in their own Swift source file under `Sources/OmuxAppShell/`, consistent with the module boundary requirement that shell concerns are partitioned rather than concentrated in one file.

#### Scenario: Extracted components are in dedicated files
- **WHEN** a developer navigates the `Sources/OmuxAppShell/` directory
- **THEN** `SidebarContainerView.swift`, `CollapsibleSectionHeaderView.swift`, and `CountBadgeView.swift` exist as distinct files, separate from `WorkspaceWindowController.swift`

#### Scenario: WorkspaceWindowController.swift no longer contains extracted type definitions
- **WHEN** `WorkspaceWindowController.swift` is inspected after extraction
- **THEN** the type definitions for `SidebarContainerView`, `CollapsibleSectionHeaderView`, and `CountBadgeView` are absent from that file
