## Context

OpenMUX currently models workspace layout with OpenMUX-native `Workspace`, `TabLayoutNode`, `PaneStack`, and `Pane` types. A split-tree leaf hosts one pane-local tab stack, and the AppKit shell renders each leaf with `PaneStackView`, `PaneHeaderView`, and a tab strip of `PaneTabButton` controls above a hosted terminal surface.

Existing split actions create a new terminal pane from the active local pane tab and insert it using the layout model. Existing pane-tab actions create, focus, and close local tabs within a stack. Drag-to-split is different because it moves an existing pane tab, including its terminal session identity, from its current stack into a newly split stack based on a spatial drop direction.

This must remain shell-level workspace behavior. The terminal runtime should continue to host terminal surfaces inside panes; it should not own drag state, split-tree decisions, or pane tab movement.

## Goals / Non-Goals

**Goals:**

- Support native AppKit drag initiation from pane-local tab buttons.
- Compute a deterministic split intent from drag location: left, right, up, or down.
- Render a lightweight split preview highlight over the eligible target pane stack while dragging.
- Move the dragged pane tab into a newly created split without recreating or tearing down its terminal session.
- Preserve focus and persistence through existing workspace model updates.
- Keep the implementation original, small, and local to AppKit shell and core workspace layout operations.

**Non-Goals:**

- Do not introduce webviews, browser drag infrastructure, or background drag services.
- Do not expose libghostty or terminal-runtime-specific types in workspace layout APIs.
- Do not support cross-window, cross-workspace, or Finder-style external drops in this change.
- Do not change terminal text selection or pointer behavior inside terminal viewports.
- Do not add a configurable plugin surface for drag behavior in the first implementation.

## Decisions

### Decision: Represent Drop Direction With an OpenMUX-Native Direction Type

Use an OpenMUX-native directional concept for drag splitting, aligned with the existing left/right/up/down direction vocabulary already used by resize behavior. The direction maps to a split axis and insertion side: left/right use columns, up/down use rows.

Alternative considered: reuse only `PaneSplitAxis`. Axis alone is insufficient because columns does not distinguish left from right and rows does not distinguish up from down.

### Decision: Add a Move-And-Split Workspace Operation

Add a core workspace operation that moves an existing pane tab into a newly created pane stack split adjacent to a target stack. The operation should detach the pane from its source stack, reject invalid moves, insert the new stack on the requested side of the target, focus the moved pane, and collapse any now-empty source stack through existing split-tree normalization.

Alternative considered: implement drag-to-split as close plus create. That would lose the existing terminal session identity and could tear down runtime state, scrollback, title metadata, and hooks context. The operation must move the pane object rather than recreate it.

### Decision: Keep Drag State in AppKit Shell Chrome

Pane tab buttons should act as native drag sources, and the layout area should act as the drag destination. The shell should track a transient drag state containing the dragged pane ID, source pane stack ID, current target stack ID, and current split direction. This state should live in the window/layout view layer and should not be persisted.

Alternative considered: store drag state in `WorkspaceController`. Controller state is appropriate for committed workspace changes, but transient pointer hover and preview state belongs in view code so it does not pollute model contracts or persistence.

### Decision: Compute Split Intent From Target Bounds Quadrants

For an eligible target pane stack, compute intent by comparing the drag point to the stack bounds. The nearest edge wins: points nearer the left edge preview split-left, nearer right previews split-right, nearer top previews split-up, and nearer bottom previews split-down. A small center dead zone may be used to avoid flicker; hovering in the dead zone should either keep the last stable intent for that target or show no valid preview.

Alternative considered: divide the target into four fixed triangular regions. Edge-distance logic is simpler to test, handles non-square panes better, and matches the visual goal of dragging toward an edge.

### Decision: Render Preview as an Overlay, Not Layout Mutation

Render the split preview as a non-interactive AppKit overlay over the target pane stack. The overlay should use the active theme accent color, be clearly visible against terminal content, and update only when target or direction changes. Layout mutation happens only on drop.

Alternative considered: temporarily mutate the split tree during drag. That would be expensive, harder to cancel reliably, and likely to disturb terminal focus and surface sizing during hover.

### Decision: Reuse Shared Action/Event Boundaries After Commit

The committed drop should flow through a controller method rather than mutating views directly. The controller can publish a control-plane event and emit hooks later using stable OpenMUX identifiers such as workspace ID, tab ID, source stack ID, target stack ID, pane ID, and direction. Initial implementation can keep external automation unchanged while preserving a clean place to expose events.

Alternative considered: make drag a view-only model mutation. That would bypass existing controller responsibilities for focus, persistence notifications, hooks, and control-plane event consistency.

## Risks / Trade-offs

- Drag handling steals terminal input focus -> Restrict drag sources to pane tab chrome and keep terminal viewport pointer events routed through existing terminal view behavior.
- Direction preview flickers near pane center or split borders -> Use stable hit testing and only update preview when the resolved target/direction changes, with a small dead zone if needed.
- Moving the last pane out of a source stack collapses more layout than expected -> Reuse and test existing detach/collapse normalization in `TabLayoutNode` and reject moves that would leave no valid layout.
- Dropping onto the source stack can create confusing no-op splits -> Treat source-to-source drops as invalid unless the drop target and direction would produce a meaningful layout change that preserves the moved pane.
- Preview overlay may obscure terminal content -> Use translucent fill and border, avoid intercepting events, and remove immediately on cancel or drop.
- Future hooks might require richer event payloads -> Include source stack, target stack, direction, pane, tab, and workspace identifiers in the controller-level operation from the start.

## Migration Plan

No persisted data migration is required. Existing workspaces, panes, tabs, and terminal sessions remain valid.

Implementation can be rolled out behind normal native shell behavior: if drag registration or a drop is invalid, the shell cancels the drag and leaves layout unchanged. Rollback removes the drag source/destination wiring and the move-and-split operation without changing existing split, create, focus, or close actions.

## Open Questions

- Should the initial interaction allow dragging a tab from a stack with only one pane tab, causing the source stack to collapse, or should that be delayed until multi-tab stacks only?
- Should dropping onto the same source stack be rejected entirely, or should it allow re-splitting the active tab out of its current stack when the source stack contains multiple tabs?
- Should committed drag-to-split publish a new dedicated event name, or reuse pane-tab moved plus pane split semantics once action events are expanded?
