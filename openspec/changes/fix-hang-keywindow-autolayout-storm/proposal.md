## Why

OpenMUX hangs with a spinning beachball (12+ seconds unresponsive) when its window becomes key after prolonged use. The hang is caused by a cascading failure: the process footprint reaches 65 GB (likely from leaked terminal surface resources over ~5 days of uptime), and every key-window transition triggers a full view-hierarchy rebuild that tears down every `NSLayoutConstraint` through deep recursive Auto Layout engine churn. With an enormous constraint graph from accumulated views, a single `removeFromSuperview` inside `PaneCardView.configure` locks the main thread in `NSISEngine.removeConstraintWithMarker` -> `NSBitSetFindNext` for seconds. This makes the terminal unusable at the worst possible moment — when the user just switched back to it.

The symptom is catastrophic, but the contributing factors are separable: a memory accumulation problem makes the reconciliation path slow, and the reconciliation path itself makes the problem worse by removing/re-adding subviews on every key-window event instead of mutating in place.

## What Changes

- **Guard `windowDidBecomeKey` against no-op calls**: Skip `refreshTerminalPresentation` when the window is already key and the workspace hasn't changed since the last refresh — a single boolean guard prevents the entire cascade from firing redundantly.
- **Debounce presentation-state-driven refreshes**: When multiple window/app state notifications fire in the same runloop turn (common on workspace switches), coalesce them into a single deferred update instead of triggering N full reconciliations.
- **Replace `removeFromSuperview` full-teardown in `PaneCardView.configure` with in-place mutation**: Instead of `container.arrangedSubviews.forEach { removeArrangedSubview; removeFromSuperview }`, update header and renderer subviews in-place. Only remove/add when the view identity actually changes. This eliminates the deep Auto Layout engine recursion (`_setLayoutEngine:` -> `_setLayoutEngine:`…) seen in the stacktrace.
- **Add guard in `update(workspace:)` against redundant structural rebuilds**: When the workspace identity and focused tab are identical to the previous update and only non-structural metadata changed, short-circuit the sidebar/canvas rebuild path early.
- **Add regression tests**: Tests that verify the key-window handler is idempotent, that `PaneCardView.configure` does not tear down unchanged subviews, and that multiple rapid workspace updates are coalesced.

## Capabilities

### New Capabilities
- `hang-keywindow-guard`: Idempotent key-window handling that skips redundant workspace refresh when window already has focus and workspace state is unchanged.
- `panecard-inplace-mutation`: `PaneCardView.configure` mutates arranged subviews in-place instead of tearing them all down and rebuilding, preserving Auto Layout engine continuity for unchanged views.

### Modified Capabilities
- `workspace-render-reconciliation`: Adds requirement that `reconcileLayoutView` and `refreshTerminalPresentation` SHALL be safe to call multiple times within a single event-loop turn without causing redundant full-hierarchy teardown. Updates the "non-structural update reuses pane host views" scenario to also cover the key-window transition case.
- `workspace-state-write-coalescing`: Broadens coalescing to include presentation-state refresh callbacks (key window, app active/inactive, occlusion changes), not just persistence writes.

## Impact

- **Affected code**:
  - `Sources/OmuxAppShell/WorkspaceShellViewController.swift` — `windowDidBecomeKey`, `windowDidResignKey`, `windowPresentationStateDidChange`, `applicationPresentationStateDidChange`, `refreshTerminalPresentation`, `update(workspace:)`
  - `Sources/OmuxAppShell/PaneViews.swift` — `PaneCardView.configure(headerView:statusText:paneRenderer:theme:focused:windowIsKey:inactiveOpacity:)`
  - `Sources/OmuxAppShell/WorkspaceController.swift` — `ensureVisibleTerminalSurfaces` (caller, no behavioral change needed)
  - `Tests/OmuxAppShellTests/OmuxAppShellTests.swift` — new test cases
- **API changes**: None. All changes are internal.
- **Bridge boundary**: Unchanged. No libghostty types or APIs are touched.
- **Hook/event coverage**: Preserved. No new state transitions are added; existing hook emissions on window state changes continue through the same code paths.
- **Keyboard correctness**: Unchanged. Focus restoration code path is preserved but made conditionally invoked.
- **Performance**: Direct improvement — eliminates O(n²) Auto Layout engine teardown on every key-window event.
