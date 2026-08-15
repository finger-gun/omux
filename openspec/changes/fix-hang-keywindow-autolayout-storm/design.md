## Context

The hang reported in the crash log (`crash-log.txt`) shows a 12.71s main-thread block during `windowDidBecomeKey`. The stacktrace reveals a deep recursion through `_setLayoutEngine:` within `CoreAutoLayout`, triggered by `PaneCardView.configure` calling `removeFromSuperview` on all arranged subviews. The process had a 65 GB memory footprint and 36 threads after ~5 days of uptime.

The current code at `WorkspaceShellViewController.windowDidBecomeKey` (line 393) unconditionally calls `refreshTerminalPresentation(for:restoreFocusIfPossible:)`, which in turn calls both `ensureVisibleTerminalSurfaces` (reconciles terminal surface visibility across all panes) and `update(workspace:)` (rebuilds the entire workspace UI including sidebar, canvas layout, and pane cards). The `WorkspaceRenderReconciliationPlanner` classifies updates as `initial`, `nonStructural`, or `structural`, but the key-window path does not consult it.

`PaneCardView.configure` (line 785 in PaneViews.swift) unconditionally removes all arranged subviews and re-adds them, even when the header and pane renderer are the same objects. Each `removeFromSuperview` cascades through `_setLayoutEngine:` deep into `CoreAutoLayout`, which — with a large constraint graph — burns CPU in `NSBitSetFindNext`.

The affected code is entirely within the app shell layer; the terminal bridge boundary is not involved.

## Goals / Non-Goals

**Goals:**
1. Prevent `windowDidBecomeKey` from triggering a full refresh when the window is already key and workspace state is unchanged.
2. Eliminate the `removeFromSuperview` teardown in `PaneCardView.configure` when subview identity is unchanged.
3. ~~Add a short-circuit in `update(workspace:)` for repeated calls with identical workspace/tab identity.~~ **Dropped during implementation — see Decision 3.**
4. Add regression tests for idempotency of key-window refresh and in-place pane card mutation.

**Non-Goals:**
- Fixing the 65 GB memory footprint. That is a separate investigation into terminal surface/buffer lifecycle leaks, likely in `CGhosttyRuntime` surface management or scrollback buffering.
- Fixing thread leakage (stale `renderer`, `io`, `cf_release` threads). That is a separate issue in the bridge boundary teardown.
- Changing the `WorkspaceRenderReconciliationPlanner` classification logic. The planner already correctly identifies `nonStructural` vs `structural` updates.
- Adding persistent caching beyond the lifecycle of a single update call.

## Decisions

### Decision 1: Boolean guard on `windowDidBecomeKey` instead of operation tracking

**Chosen**: Track `lastRefreshedWorkspaceID` and `lastWindowPresentationState` on the controller. In `windowDidBecomeKey`, compare against current state and return early if nothing changed.

**Alternative considered**: A `needsRefresh` flag with deferred dispatch. Rejected because it adds timing complexity and the boolean guard is simpler and more predictable.

**Rationale**: The most common hang trigger is the window becoming key when it already was key (e.g., click on window chrome, Cmd-Tab back to OpenMUX when it's already frontmost). A single identity check eliminates this entire class of redundant refresh.

### Decision 2: In-place mutation in `PaneCardView.configure` instead of full teardown

**Chosen**: Track the previously configured pane renderer identity. In `configure`, only call `removeFromSuperview` when the header or renderer identity actually changed. For the pane renderer view, check identity against `paneRenderer.rootPaneView` from the prior call; for header, check pointer equality.

**Alternative considered**: Using `isHidden` toggles instead of removing subviews. Rejected because it doesn't actually solve the Auto Layout churn — the hidden views still have constraints in the engine. The real fix is to not remove/re-add at all.

**Rationale**: The stacktrace shows 6+ levels of recursive `_setLayoutEngine:` calls, all triggered by a single `removeFromSuperview` in `configure`. Eliminating the teardown when views are unchanged eliminates the entire recursive chain.

### Decision 3: `update(workspace:)` short-circuit — DROPPED (unsafe & redundant)

**Original plan**: At the top of `update(workspace:)`, after the pane-tab-drag guard, compare `workspace.id`/`focusedTabID` (later revised to full `Workspace` value equality) against `currentWorkspace`. If identical, only reconcile terminal surface visibility without rebuilding the canvas/sidebar.

**Dropped**: `update(workspace:)` is the single render entry point that **also rebuilds the workspace sidebar**, and the sidebar renders from state that is *independent of the active workspace value*:
- the workspace **list order** (`controller.allWorkspaces()`, mutated by `moveWorkspace`)
- per-workspace **collapse** flags (`collapsedWorkspaceIDs`, `isWorkspacesSectionCollapsed`)
- **pane-metadata row overrides** (`paneMetadataRowsOverridesByPaneID`)

Any short-circuit keyed on the active workspace (whether `id`+`focusedTabID` or full value equality) therefore drops legitimate sidebar re-renders and regresses existing behavior — confirmed by `testWorkspaceWindowReflectsReorderedWorkspaceSidebarOrder`, `testWorkspaceSidebarCollapseHidesPaneRowsUntilWorkspaceFocus`, and `testWorkspaceWindowAppliesPaneMetadataRowOverridesInSidebar`, all of which pass on the clean tree and fail with the short-circuit in place.

**Why it's safe to drop**: The short-circuit was only ever a *backstop*. The hang is fixed at the root by Decision 2 (in-place pane-card mutation eliminates the constraint-teardown storm), and its trigger is suppressed by Decision 1 (key-window guard) plus the runloop coalescing (Section 4 of tasks). The residual value of the short-circuit did not justify the sidebar-correctness risk.

### Decision 4: ~~Preserve `ensureVisibleTerminalSurfaces` call even on short-circuit~~ — DROPPED with Decision 3

Obsolete: there is no short-circuit path. `update(workspace:)` still calls `ensureVisibleTerminalSurfaces` on the normal render path, and the coalesced `refreshTerminalPresentation` reconciles surface visibility for pure presentation-state changes.

## Risks / Trade-offs

- **[Resolved] Stale UI after short-circuit**: This risk is moot — the `update(workspace:)` short-circuit was dropped (see Decision 3). The sidebar and canvas are re-rendered on every real `update(workspace:)`, so cross-workspace state (list order, collapse, pane metadata) is never stale.
- **[Risk] `PaneCardView` caches a stale renderer reference**: If the renderer's `rootPaneView` changes identity without `configure` being called, the cached reference becomes stale. → **Mitigation**: The renderer identity is always set through `configure`; no external code path changes `paneRenderer` on `PaneCardView`. The `PaneStackView` is the sole owner of renderer identity and it already guards against unnecessary recreation (line 575: `paneRenderer.representedPaneID != activePane.id`).
- **[Trade-off] Single refresh-per-event is less responsive to rapid workspace changes**: If a user script sends 3 rapid workspace-change RPC commands, only the last one refreshes the UI. → This is already the behavior under `WorkspaceRenderReconciliationPlanner`. No change to the update path is involved — we're only preventing no-op refreshes.
