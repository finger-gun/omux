## 1. Configuration

- [x] 1.1 Add `workspace.isolate_shell_history` to config defaults, parsing, validation, JSON exposure, and generated config output.
- [x] 1.2 Add config tests for default enabled behavior, explicit disabled behavior, invalid non-boolean diagnostics, and generated config contents.

## 2. Session Launch Environment

- [x] 2.1 Add an OpenMUX-owned workspace shell environment helper that computes workspace context variables and stable per-workspace history paths.
- [x] 2.2 Route new workspace, split, pane-tab, worktree pane-tab, and restored pane session launches through the workspace shell environment helper.
- [x] 2.3 Add app-shell tests proving different workspaces get different `HISTFILE` values, panes in one workspace share a value, disabled config omits `HISTFILE`, and restored panes keep workspace context.

## 3. Bridge Boundary

- [x] 3.1 Ensure bridge tests cover workspace context and history environment propagation without adding workspace policy to the bridge.

## 4. Documentation and Verification

- [x] 4.1 Document workspace shell history isolation, the opt-out setting, and the fact that shell startup files may override `HISTFILE`.
- [x] 4.2 Run focused config/app-shell/terminal-bridge tests and OpenSpec validation for the change.
