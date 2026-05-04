## 1. Native Shortcut Ladder

- [x] 1.1 Keep pane creation on existing `Cmd+D` and `Cmd+Shift+D` shortcuts without adding `Cmd+Shift+T`.
- [x] 1.2 Add `Cmd+Shift+W` as a remove-active-pane shortcut and remove the old `Cmd+Shift+Backspace` pane-delete binding.
- [x] 1.3 Add `Cmd+Shift+N` as a delete/close-active-workspace shortcut while preserving `Cmd+N`.
- [x] 1.4 Update menu labels, key equivalents, and validation so existing shortcuts continue to work.

## 2. Input Allowlist

- [x] 2.1 Extend `OpenMUXShortcutClassifier` to recognize the new exact Command+Shift remove/close shortcuts.
- [x] 2.2 Add input tests proving the new shortcuts are shell-owned.
- [x] 2.3 Add regression tests proving unknown Command chords, Option chords, and right-Option/international input remain terminal-owned.

## 3. Control Plane and CLI Parity

- [x] 3.1 Add additive control-plane methods for `workspace.close` and `pane.remove`.
- [x] 3.2 Implement control-plane handlers that close the active or explicit workspace and remove the focused or targeted pane.
- [x] 3.3 Add CLI commands `workspace-close [workspace-id]` and `pane-remove [target]`.
- [x] 3.4 Preserve existing CLI commands for workspace open, pane split, and pane-tab create/close.
- [x] 3.5 Add CLI/control-plane tests for success, explicit target handling, and failure cases.

## 4. Validation

- [x] 4.1 Run OpenSpec validation for `scope-shortcut-ladder`.
- [x] 4.2 Run targeted Swift tests for input, app-shell shortcuts, CLI, and control-plane behavior.
- [x] 4.3 Run the repository verification command if targeted tests pass.
