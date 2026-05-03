## 1. Control-Plane Contract

- [x] 1.1 Add OpenMUX-native history request/response types for active-workspace, pane, and all-workspace scopes.
- [x] 1.2 Add a local JSON-RPC method for bounded terminal history reads with max-lines and max-bytes options.
- [x] 1.3 Return per-pane topology metadata, captured text, bounds metadata, truncation status, and unavailable reasons.
- [x] 1.4 Add control-plane tests for scope resolution, invalid pane handling, bounded metadata, and unavailable pane results.

## 2. App-Shell History Resolution

- [x] 2.1 Resolve active workspace, pane ID, and all-workspace history scopes from live workspace/tab/pane topology.
- [x] 2.2 Capture each live pane through the terminal bridge and persist bounded history per pane/pane-tab in workspace state.
- [x] 2.3 Preserve read-only behavior by ensuring history requests do not send input, mutate terminal state, or render UI.
- [x] 2.4 Add app-shell tests for active workspace, pane-specific, all-workspace grouping, per-pane persistence, and no-UI side effects.

## 3. Terminal Bridge Boundary

- [x] 3.1 Ensure the bridge exposes bounded history snapshots through OpenMUX-native types with no Ghostty types outside the bridge.
- [x] 3.2 Normalize bridge failures into explicit unavailable results for app-shell/control-plane callers.
- [x] 3.3 Add or update bridge tests for byte/line limits, truncation reporting, and unavailable surface handling.

## 4. CLI and Hook Usability

- [x] 4.1 Add `omux history`, `omux history <pane-id>`, and `omux history all` command parsing and usage text.
- [x] 4.2 Add readable grouped output with workspace, tab, pane, session, cwd, truncation, and unavailable headers.
- [x] 4.3 Add JSON output mode for hook handlers and scripts.
- [x] 4.4 Add CLI tests for no-argument, pane-specific, all-workspace, JSON, and invalid-argument behavior.

## 5. Verification and Documentation

- [x] 5.1 Document history command behavior and hook usage in the relevant CLI/hook docs.
- [x] 5.2 Run OpenSpec validation for `expose-pane-history`.
- [x] 5.3 Run the existing Swift test suite or targeted package tests covering the changed modules.
