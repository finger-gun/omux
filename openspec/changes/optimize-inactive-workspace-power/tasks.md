## 1. Bridge Visibility Boundary

- [x] 1.1 Add an OpenMUX-native terminal surface visibility API to the terminal bridge protocol without exposing libghostty types outside `OmuxTerminalBridge`.
- [x] 1.2 Extend the null/fake runtime implementations used by tests to record surface visibility transitions.
- [x] 1.3 Map the production runtime visibility API to libghostty surface occlusion inside `CGhosttyRuntime`.
- [x] 1.4 Refresh or tick a surface when it transitions from hidden to visible so current terminal output is presented immediately.
- [x] 1.5 Add bridge/runtime tests proving hidden visibility does not destroy surfaces, detach sessions, or prevent later visible refresh.

## 2. Focus And App Lifecycle Separation

- [x] 2.1 Review current surface focus handling and separate app/window focus from individual pane focus where they are conflated.
- [x] 2.2 Drive app/window focus from AppKit window lifecycle rather than from unfocusing an individual pane.
- [x] 2.3 Add tests proving unfocusing one terminal pane does not mark the entire terminal runtime unfocused while the OpenMUX window remains active.
- [x] 2.4 Verify keyboard/input routing remains limited to the visible focused terminal surface and does not change Option/Alt, right-Option, dead-key, compose, or IME behavior.

## 3. Shell Visibility Derivation

- [x] 3.1 Add an app-shell helper that derives visible terminal pane IDs from active workspace, focused tab, pane-stack focused pane tabs, floating modals, and window state.
- [x] 3.2 Mark panes in inactive workspaces as hidden while keeping their workspace model, pane model, and session descriptors intact.
- [x] 3.3 Mark non-focused pane-stack terminal tabs as hidden while preserving pane-tab state.
- [x] 3.4 Include minimized, hidden, and occluded window state in terminal surface visibility derivation.
- [x] 3.5 Make visibility updates idempotent so repeated reconciliation does not produce redundant bridge calls.

## 4. Reconciliation Integration

- [x] 4.1 Apply derived terminal surface visibility during workspace render reconciliation without rebuilding unrelated pane hosts.
- [x] 4.2 Update workspace switching so newly visible terminal panes are unhidden and previously visible terminal panes are hidden.
- [x] 4.3 Update pane-tab switching so only the visible pane tab in each stack is marked visible.
- [x] 4.4 Update floating modal show/hide/dock flows so terminal surface visibility follows modal presentation.
- [x] 4.5 Add app-shell reconciliation tests covering inactive workspace panes, inactive pane-stack tabs, floating modals, and window hiding.

## 5. Session Liveness And Persistence

- [x] 5.1 Add tests showing a hidden inactive workspace terminal session can continue producing output.
- [x] 5.2 Add tests showing hidden-session title, progress, bell, clipboard/effects callbacks, and child lifecycle events still flow through existing terminal action handling where test infrastructure supports them.
- [x] 5.3 Add scrollback persistence coverage for output produced while a surface is hidden.
- [x] 5.4 Verify unavailable hidden-surface capture follows existing no-fabricated-scrollback behavior.
- [x] 5.5 Verify restored historical scrollback remains distinguishable from live output produced while hidden.

## 6. Runtime Power Baseline

- [x] 6.1 Document a repeatable local idle-power profile scenario with multiple workspaces, only one visible workspace, and live processes in inactive workspaces.
- [x] 6.2 Include commands for collecting CPU, memory, elapsed runtime, thread count, sampled stacks, and optional process energy data.
- [x] 6.3 Include guidance for permission-restricted commands such as `powermetrics` and how to record missing measurements.
- [x] 6.4 Capture a before-change profile or document the current observed sample as the baseline for this change.
- [ ] 6.5 Capture an after-change profile using the same scenario and compare renderer, CVDisplayLink, Metal, Core Animation, IOSurface, CPU, memory, and energy signals.

## 7. Verification

- [x] 7.1 Run focused bridge and app-shell tests for visibility, focus, reconciliation, and scrollback behavior.
- [x] 7.2 Run the broader Swift test suite with the approved project test command.
- [ ] 7.3 Manually verify inactive workspace processes continue running while their surfaces are hidden.
- [ ] 7.4 Manually verify switching back to an inactive workspace shows current terminal output without restarting the session.
- [ ] 7.5 Record any remaining renderer/display-link activity in the after profile and classify it as expected visible-surface work, unresolved hidden-surface work, or unrelated background work.
