# shared-sidebar-base Specification

## Purpose
Specifies the `SidebarContainerView` base class that encapsulates shared sidebar container infrastructure for `WorkspaceSidebarView` and `WorkspaceVaultSidebarView`.

## Requirements

### Requirement: A shared sidebar base class SHALL encapsulate common sidebar container infrastructure
The `SidebarContainerView` class SHALL provide shared width constraint management, toggle/collapse behavior, and theme application as a concrete `NSView` subclass. Both `WorkspaceSidebarView` and `WorkspaceVaultSidebarView` SHALL inherit from it rather than independently reimplementing these concerns.

#### Scenario: Width constraint is managed by the base class
- **WHEN** a sidebar subclass is initialized
- **THEN** the width constraint is owned and managed by `SidebarContainerView`, not redeclared in each subclass

#### Scenario: Theme application flows through the base class
- **WHEN** `apply(theme:)` is called on a sidebar instance
- **THEN** the base class applies shared theme properties (background, border) before delegating to the subclass for content-specific theming

#### Scenario: Toggle behavior is inherited, not duplicated
- **WHEN** the sidebar is shown or hidden via the toggle action
- **THEN** the collapse/expand animation and constraint update are executed by `SidebarContainerView`, with subclasses able to hook in via an override point

### Requirement: Sidebar subclasses SHALL retain full control of their content layout
`SidebarContainerView` SHALL only own infrastructure concerns. Content layout, widget composition, and subclass-specific behavior SHALL remain exclusively in each subclass.

#### Scenario: Subclass-specific widgets are not affected by base class extraction
- **WHEN** `WorkspaceSidebarView` renders its workspace list widgets
- **THEN** widget composition and layout logic remains in `WorkspaceSidebarView`, not in `SidebarContainerView`

#### Scenario: Subclass-specific widgets are not affected on the vault side
- **WHEN** `WorkspaceVaultSidebarView` renders its agent session and worktree widgets
- **THEN** widget composition and layout logic remains in `WorkspaceVaultSidebarView`, not in `SidebarContainerView`
