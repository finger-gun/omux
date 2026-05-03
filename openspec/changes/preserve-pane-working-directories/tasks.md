## 1. Reproduce and protect cwd persistence

- [x] 1.1 Add tests covering multiple workspaces and panes with distinct reported working directories saved and restored.
- [x] 1.2 Add tests proving splits and pane tabs inherit the focused/source pane's latest working directory.

## 2. Implement durable pane cwd updates

- [x] 2.1 Ensure terminal cwd actions update `Pane.session.workingDirectory` before persistence snapshots are created.
- [x] 2.2 Ensure persistence sanitization preserves per-pane working directories while clearing transient terminal status.
- [x] 2.3 Ensure restore attaches each pane using the saved pane-specific working directory.

## 3. Validate behavior

- [x] 3.1 Run targeted app-shell and terminal bridge tests for cwd persistence and action dispatch.
- [x] 3.2 Run the repository test suite or the closest existing test target set.
