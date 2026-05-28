## Context

`WorkspaceWindowController.swift` is currently ~10,048 lines. All UI components — both sidebars, widget headers, count badges, section rows — are declared `private` or `fileprivate` inside that file. This makes them:

- Impossible to unit test in isolation
- Inaccessible to future plugin UI contribution points
- Prone to drift and duplication (the left and right sidebars have already diverged with no shared base)

The existing `workspace-window-shell-boundaries` spec already mandates that shell concerns be partitioned into dedicated modules. This change begins executing on that requirement for the UI primitive layer specifically.

No behavior changes. No public API, CLI, IPC, hook, or control-plane surface is affected. This is a structural refactor only.

## Goals / Non-Goals

**Goals:**
- Extract `CountBadgeView` and `CollapsibleSectionHeaderView` into their own files with `internal` visibility
- Introduce a `SidebarContainerView` base class that both `WorkspaceSidebarView` and `WorkspaceVaultSidebarView` inherit from, eliminating the duplicated width constraint, toggle, and theme-application logic
- Raise visibility of extracted types to `internal` so they are consumable by tests and future modules within `OmuxAppShell`
- Keep all extracted files within `Sources/OmuxAppShell/` — no new SPM targets for this change

**Non-Goals:**
- Creating a separate `OmuxUI` SPM target or package (deferred — requires broader module boundary planning)
- Making any component `public` (plugin UI contracts are out of scope for this change)
- Changing sidebar behavior, layout metrics, or theme values
- Touching input handling, keybindings, or the libghostty bridge

## Decisions

### 1. Stay within `OmuxAppShell` — no new SPM target yet

**Decision**: Extract into new files under `Sources/OmuxAppShell/` rather than creating a new `OmuxUI` module.

**Rationale**: A new SPM target requires defining stable `public` API contracts. We are not ready to commit to a public UI component API surface. Moving to `internal` within the same module is the minimum viable step that unlocks testability and eliminates duplication without creating premature API lock-in.

**Alternative considered**: Create `Sources/OmuxUI/` as a new SPM library target. Rejected — it requires all extracted types to be `public`, and no stable plugin UI contract exists yet.

---

### 2. Base class over protocol for sidebar containers

**Decision**: Use a concrete `SidebarContainerView: NSView` base class rather than a protocol for the shared sidebar abstraction.

**Rationale**: Both sidebars share layout infrastructure (Auto Layout constraints, drag-resize handles, toggle/collapse animation, `apply(theme:)` wiring) that is better expressed through shared stored properties and concrete methods on a base class than through protocol default implementations. AppKit view hierarchies are inherently class-based; protocol composition here would add indirection without benefit.

**Alternative considered**: `SidebarContaining` protocol with default implementations via extension. Rejected — Swift protocol extensions cannot hold stored properties, requiring each conformer to redeclare width constraints, drag coordinators, and theme state. That's the exact duplication we're eliminating.

---

### 3. File-per-component, flat directory layout

**Decision**: One new Swift file per extracted component type, all placed directly under `Sources/OmuxAppShell/`. No subdirectory grouping yet.

**Rationale**: The codebase does not yet have a settled directory convention for UI sub-concerns. Introducing a `UI/` or `Views/` subdirectory at this point is an opinion that should wait for a broader file layout decision. Flat placement is consistent with the existing source tree.

**Files to create**:
- `SidebarContainerView.swift` — base class for both sidebars
- `CollapsibleSectionHeaderView.swift` — widget/section header
- `CountBadgeView.swift` — number badge used by section headers

---

### 4. Visibility: `internal`, not `public`

**Decision**: All extracted types are `internal` (Swift default — no explicit modifier needed).

**Rationale**: `internal` is visible across the entire `OmuxAppShell` module, enabling unit tests in `OmuxAppShellTests` to instantiate components directly. No plugin or external module needs access yet. Promoting to `public` is a one-line change when a stable plugin UI contract is defined.

## Risks / Trade-offs

- **Risk: Merge conflicts with parallel work on `WorkspaceWindowController.swift`** → Mitigation: This refactor should be merged before or after any unrelated changes to that file. Coordinate with active branches touching the workspace shell.
- **Risk: Auto Layout constraint ownership breaks during extraction** → Mitigation: Extract types one at a time, building and running the app after each extraction before committing.
- **Risk: Base class adds hidden coupling** → Mitigation: Keep `SidebarContainerView` thin — only width constraints, toggle infrastructure, and `apply(theme:)` hook. Subclass-specific layout stays in the subclass.

## Open Questions

- Should `SidebarContainerView` own the `SidebarDragCoordinator` reference, or should drag coordination stay in `WorkspaceShellViewController`? The coordinator bridges both sidebars, so it may belong at the controller level. Leave as-is for this change and revisit when sidebar drag behavior is specified.
- When is the right moment to introduce a `public` UI component API for plugin contributions? Defer to a future `plugin-ui-primitives` change.
