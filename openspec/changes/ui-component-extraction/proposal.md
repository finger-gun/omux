## Why

All UI components in the workspace shell — sidebars, widget headers, badges, and section rows — live inside a single 10,048-line file (`WorkspaceWindowController.swift`) with `private` visibility, making them impossible to reuse across modules, test in isolation, or consume from plugins. The left and right sidebars are independently reimplemented with no shared base, and the badge and header components that are consolidated internally cannot be reached by anything outside that file.

## What Changes

- Extract shared UI primitives (`CountBadgeView`, `CollapsibleSectionHeaderView`) from `WorkspaceWindowController.swift` into standalone, module-visible types
- Introduce a shared `SidebarView` base class or protocol so `WorkspaceSidebarView` and `WorkspaceVaultSidebarView` share layout, theming, and toggle infrastructure rather than duplicating it
- Move extracted components into their own files within the `OmuxAppShell` module (or a dedicated `OmuxUI` sub-module if appropriate)
- Raise visibility to `internal` (or higher where needed) so components can be consumed by tests and future plugin UI surfaces
- No behavioral changes to existing sidebar, header, or badge behavior

## Capabilities

### New Capabilities
- `shared-sidebar-base`: A shared base class or protocol for sidebar containers, covering width constraints, toggle/collapse behavior, and theme application — consumed by both the workspace and vault sidebars
- `ui-primitive-components`: Extracted, reusable view primitives (`CountBadgeView`, `CollapsibleSectionHeaderView`) with `internal` or higher visibility, living in their own files

### Modified Capabilities
- `workspace-window-shell-boundaries`: The module boundary rules are affected — components moving out of the monolithic controller changes the internal file layout and visibility model of `OmuxAppShell`

## Impact

- **Primary file**: `Sources/OmuxAppShell/WorkspaceWindowController.swift` (currently ~10,048 lines)
- **New files**: One or more new Swift files under `Sources/OmuxAppShell/` for extracted components
- **No API surface changes**: No CLI, IPC, JSON-RPC, hook, or control-plane events are affected — this is a pure internal structural refactor
- **No keyboard/input impact**: No input handling, keybinding, or IME code is touched
- **No libghostty bridge impact**: The terminal bridge boundary is not affected
- **Test surface**: Extracted components become independently unit-testable for the first time
- **Plugin readiness**: Raised visibility unlocks future plugin UI contribution points without requiring further refactors
