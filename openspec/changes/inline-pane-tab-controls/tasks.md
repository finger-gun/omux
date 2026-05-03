## 1. Pane Header Layout

- [x] 1.1 Refactor `PaneHeaderView` so pane-tab pills and the add-pane-tab control are arranged in one tab strip, with `+` immediately after the last local pane tab.
- [x] 1.2 Remove the separate trailing pane-tab add control from the header controls group while preserving the existing create action callback.
- [x] 1.3 Remove the separate generic close-focused-pane-tab control when per-tab close controls are available.

## 2. Per-Tab Close Controls

- [x] 2.1 Introduce a compact pane-tab control that renders the tab title and an optional inline `x` close hit target.
- [x] 2.2 Wire tab-body clicks to focus that pane tab and close-hit-target clicks to close that specific pane ID.
- [x] 2.3 Hide or disable inline close affordances when the pane stack contains only one local pane tab.
- [x] 2.4 Preserve right-click context menus for pane tabs after adding the inline close affordance.

## 3. Interaction Safety and Visual Fit

- [x] 3.1 Keep pane-tab controls as AppKit-owned pane chrome without changing terminal input routing or `libghostty` bridge boundaries.
- [x] 3.2 Ensure compact tab labels and close controls fit narrow pane headers without adding extra persistent chrome rows.
- [x] 3.3 Preserve existing keyboard shortcuts, CLI, JSON-RPC, hook, and persistence behavior.

## 4. Tests and Validation

- [x] 4.1 Add app-shell tests proving the add control is inline after the final pane tab.
- [x] 4.2 Add app-shell tests proving each close control targets its own pane tab and is unavailable for single-tab stacks.
- [x] 4.3 Add regression coverage that the generic close-focused control is no longer rendered separately.
- [x] 4.4 Run OpenSpec validation for `inline-pane-tab-controls`.
- [x] 4.5 Run targeted Swift tests for pane header and pane-tab behavior.
