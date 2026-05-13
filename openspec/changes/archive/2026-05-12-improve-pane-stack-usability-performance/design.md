## Context

OpenMUX currently updates workspace UI by rebuilding the canvas root view on each workspace change. That approach was acceptable for early foundation work, but now it causes avoidable layout churn, responder instability, and state loss risks under high-frequency updates (pane status changes, extension-pane refreshes, drag interactions). Pane-tab drag support also lacks same-stack reorder behavior, so a common tab-management action still feels incomplete.

The code path spans `WorkspaceController` state mutations, `WorkspaceShellViewController.update(workspace:)`, and `WorkspaceCanvasView.render(layoutView:theme:)`, making this a cross-cutting app-shell behavior change with performance and UX impact. This change must keep terminal input behavior and libghostty ownership boundaries untouched.

## Goals / Non-Goals

**Goals:**
- Replace full canvas teardown/rebuild with keyed reconciliation for stable pane/pane-stack identity.
- Preserve focus, responder continuity, and extension-pane host runtime state across non-structural updates.
- Add same-stack pane-tab reorder using existing pane-tab drag interactions.
- Improve app-shell update code readability by separating reconciliation logic from layout construction.
- Reduce update-time allocation/layout churn for smoother interactive performance.

**Non-Goals:**
- Replacing AppKit with a browser/webview shell model.
- Moving layout ownership into `OmuxTerminalBridge` or exposing libghostty layout types.
- Introducing background worker services for UI updates.
- Redesigning pane visual style unrelated to behavior/performance.

## Decisions

### Decision: Introduce keyed render reconciliation at pane-stack boundaries

Use stable OpenMUX identifiers (`PaneStackID`, `PaneID`) to reuse existing hosted views whenever structure is unchanged, and only rebuild affected subtrees when split topology or tab membership changes.

Alternatives considered:
- Keep full redraw and patch individual regressions ad hoc. Rejected because regressions recur and performance remains unstable.
- Centralize all update behavior in one giant render method. Rejected for maintainability/readability.

### Decision: Model “structural” vs “non-structural” workspace updates explicitly

Classify updates so non-structural changes (title/status/content updates) reuse views and preserve state; structural changes (split topology, stack membership, tab order) apply targeted subtree updates.

Alternatives considered:
- Infer update type implicitly from UI state each time. Rejected due to fragility and opaque behavior.

### Decision: Extend pane-tab drag intent to support same-stack reorder

When dragging over the source pane-stack header, resolve an insertion index and reorder pane tabs in-place instead of treating the drop as invalid. Preserve existing merge/split priorities for different-stack and outer-edge targets.

Alternatives considered:
- Add separate non-drag reorder controls only. Rejected because drag is already the primary pane-tab movement interaction.

### Decision: Keep keyboard/input behavior explicitly unchanged

All reorder/reconciliation updates remain shell-side and must not alter terminal input routing, Option/right-Option behavior, dead keys, compose keys, or IME flow.

Alternatives considered:
- Let focused-host replacement rely on default responder reassignment. Rejected due to focus flicker and intermittent input-target shifts.

### Decision: Maintain clean bridge boundary and plugin contracts

Reconciliation and reorder operate on OpenMUX model IDs and shell views only. `OmuxTerminalBridge` remains terminal surface runtime owner; plugin extension panes remain host-rendered content.

Alternatives considered:
- Directly manipulating runtime surfaces for reorder/perf tricks. Rejected because it leaks terminal-engine concerns into shell layout logic.

## Risks / Trade-offs

- [Risk] Reconciliation bugs may leave stale or miswired views. → Mitigation: add deterministic identity-mapping tests and structural/non-structural update regression coverage.
- [Risk] Reorder insertion semantics may feel inconsistent at edge positions. → Mitigation: define explicit insertion-index rules and test all header regions.
- [Risk] Focus preservation may regress for mixed terminal/extension-pane stacks. → Mitigation: add mixed-content focus continuity tests under rapid updates.
- [Risk] More update logic can increase code complexity. → Mitigation: isolate reconciliation planner/applier helpers with clear interfaces and naming.

## Migration Plan

1. Add reconciliation planner/applier primitives behind existing shell update entry points.
2. Switch canvas render path to keyed reuse for non-structural updates.
3. Add same-stack reorder drop intent + controller mutation path.
4. Add focused regression/performance tests and tune reconciliation heuristics.
5. Rollback strategy: keep a guarded fallback to full rebuild path for emergency regression isolation during rollout.

## Open Questions

- Should reorder insertion be nearest-tab-center or edge-zone based when hovering in header whitespace?
- Do we need lightweight render/update metrics in debug builds to track reconciliation effectiveness over time?
- Should future extension-pane hosts provide an explicit serializable host-state contract beyond scroll/focus continuity?

