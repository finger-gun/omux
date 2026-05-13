## Context

Current performance hotspots are concentrated in three areas:
1. Workspace persistence is triggered on frequent workspace mutations and can perform synchronous encoding and file operations.
2. Terminal event subscriptions use queue operations that become increasingly expensive as queue depth grows.
3. WorkspaceController operations frequently re-scan workspace/tab/pane trees to find pane/session targets.

These are cross-cutting concerns in app shell and control plane code, but they do not require changing terminal-engine contracts or external behavior.

## Goals / Non-Goals

**Goals:**
- Keep UI/terminal interaction responsive under frequent updates.
- Preserve terminal-first behavior and current control-plane semantics.
- Introduce explicit, testable performance invariants.

**Non-Goals:**
- Rewriting workspace model semantics.
- Redefining control-plane protocol payloads.
- Introducing background daemons or browser-based runtime components.

## Decisions

### 1) Coalesced persistence writes with bounded flush guarantees
- Introduce a persistence coordinator that coalesces rapid `onChange` bursts into a single save window.
- Persist layout-only snapshots on frequent updates; full scrollback snapshots remain periodic/termination-triggered.
- Keep explicit flush points (terminate/power-off) synchronous to preserve durability guarantees.

**Alternative considered:** Keep immediate-save semantics and optimize individual save calls only.  
**Why not chosen:** still pays repeated encode + filesystem overhead at high mutation rates.

### 2) O(1)-style event queue operations for terminal-event subscriptions
- Replace head-removal queue mechanics with deque/ring-buffer style semantics for subscription event buffers.
- Keep current ordering and subscription cancellation behavior unchanged.

**Alternative considered:** drop events aggressively when busy.  
**Why not chosen:** risks losing critical automation/hook events and surprises users.

### 3) Controller-maintained lookup indexes
- Maintain indexes from `PaneID` and `SessionID` to workspace/tab/pane location metadata.
- Rebuild indexes during full-state restoration; incrementally update on localized mutations.
- Fall back to full scan only for invariant-recovery assertions/tests.

**Alternative considered:** leave scans in place and only optimize a few call sites.  
**Why not chosen:** repeated regressions are likely; centralized index contracts provide safer long-term structure.

## Risks / Trade-offs

- **[Risk] Index drift after complex mutations** → **Mitigation:** invariant tests that compare indexed vs scanned results in test builds.
- **[Risk] Coalescing delays visibility of persisted state** → **Mitigation:** explicit flush on lifecycle boundaries and short coalescing windows.
- **[Risk] Queue rewrite alters stream behavior** → **Mitigation:** event ordering and cancellation tests for single and multi-subscriber cases.
- **[Risk] Keyboard/input regressions via lifecycle/timing changes** → **Mitigation:** retain input-path boundaries untouched; run existing input-related test suites.

## Migration Plan

1. Add persistence coordinator and wire app-delegate update callback through it.
2. Introduce queue abstraction for terminal-event subscriptions and migrate service internals.
3. Add workspace lookup-index structure and switch high-frequency call sites.
4. Add/expand tests for coalescing, queue ordering, and index invariants.
5. Rollback strategy: feature-flag or revert per slice (persistence, queue, indexes) independently.

## Open Questions

- Should persistence coalescing window be fixed or config-derived for future tuning?
- Should index invariant checks stay test-only or include lightweight debug assertions in development builds?
