## 1. Reconciliation Foundations

- [x] 1.1 Add a workspace render reconciliation planner that classifies updates as structural vs non-structural using stable `PaneStackID`/`PaneID` identity.
- [x] 1.2 Add reconciliation applier helpers that reuse identity-stable pane stack/host views and replace only affected subtrees.
- [x] 1.3 Refactor shell update flow to route through reconciliation helpers with clear, testable boundaries (planner, applier, fallback path).

## 2. Same-Stack Pane-Tab Reorder

- [x] 2.1 Extend pane-tab drag intent resolution to support source-stack header drops as reorder operations with deterministic insertion-index rules.
- [x] 2.2 Add a controller action for same-stack pane-tab reorder that preserves pane/session/surface identity and focuses the moved pane.
- [x] 2.3 Keep existing merge/split priority behavior intact for different-stack and outer-edge drop paths.

## 3. State Continuity and Performance

- [x] 3.1 Ensure non-structural updates preserve responder/focus continuity for terminal and extension panes.
- [x] 3.2 Ensure identity-stable extension pane hosts preserve runtime continuity (including scroll continuity) during non-structural updates.
- [x] 3.3 Add lightweight debug-only reconciliation metrics (reused hosts vs rebuilt hosts) to validate reduced view churn during rapid updates.

## 4. Regression Coverage

- [x] 4.1 Add app-shell tests proving non-structural updates do not rebuild unaffected pane hosts.
- [x] 4.2 Add tests for same-stack pane-tab reorder semantics across header regions and edge cases.
- [x] 4.3 Add regression tests for mixed terminal/extension-pane focus and input-target continuity during rapid update sequences.
- [x] 4.4 Add tests confirming reorder/reconciliation changes do not alter terminal keyboard routing semantics for Option/right-Option, dead keys, compose keys, and IME paths.

## 5. Documentation and Verification

- [x] 5.1 Update developer docs to describe reconciled render behavior and same-stack reorder support.
- [x] 5.2 Update user-facing pane-tab/drag workflow docs to reflect source-stack reorder behavior.
- [x] 5.3 Run targeted app-shell and terminal/input regression suites plus OpenSpec validation for this change.
