## 1. Configurable Workspace Root

- [x] 1.1 Add `OmuxConfigWorkspace` with `defaultRootPath`, defaulting to the current user's home directory.
- [x] 1.2 Extend TOML decoding to accept `[workspace] default_root_path`, reject unknown workspace keys, expand `~`, standardize paths, and diagnose invalid values.
- [x] 1.3 Update starter config and user documentation for `[workspace] default_root_path`.
- [x] 1.4 Add config loader tests for unset, configured, invalid, and unknown workspace root settings.

## 2. Workspace Open Path Resolution

- [x] 2.1 Thread the effective default workspace root into app shell startup and shared workspace creation.
- [x] 2.2 Make first launch without persisted state and sidebar/menu workspace creation use the configured default root.
- [x] 2.3 Make control-plane `workspace.open` resolve missing path data through the configured default root.
- [x] 2.4 Update `omux open` to accept an optional path and preserve explicit path behavior.
- [x] 2.5 Add app shell and CLI tests for default-root and explicit-path open behavior.

## 3. Shared Pane and Pane-Tab Navigation Actions

- [x] 3.1 Add core/model helpers for cycling pane-local tabs within a pane stack and panes in visible split-tree order.
- [x] 3.2 Add `WorkspaceController` shared actions for next/previous pane-local tab focus and next/previous pane focus.
- [x] 3.3 Emit existing focus events only for actual focus changes and keep single-target navigation inert.
- [x] 3.4 Add app shell tests for wrapping, previous/next behavior, and inert single-target navigation.

## 4. Control Plane and CLI Parity

- [x] 4.1 Add control-plane methods for pane-local tab next/previous and pane next/previous navigation.
- [x] 4.2 Return chainable focused terminal context metadata from navigation methods.
- [x] 4.3 Add CLI commands `pane-tab-next`, `pane-tab-prev`, `pane-next`, and `pane-prev`.
- [x] 4.4 Add CLI/control-plane tests for all new navigation commands and missing-target failures.

## 5. Native Shortcuts and Input Routing

- [x] 5.1 Add native menu/key commands for `Cmd+T`, `Cmd+W`, `Ctrl+Tab`, and `Ctrl+Shift+Tab`.
- [x] 5.2 Resolve the current `Cmd+W` workspace-delete conflict so it closes the focused pane-local tab instead.
- [x] 5.3 Extend `OpenMUXShortcutClassifier` to allowlist only the new exact navigation chords.
- [x] 5.4 Add input tests proving the new chords are shortcuts and unrelated Control/Option/composition input remains terminal-owned.

## 6. Validation

- [x] 6.1 Run OpenSpec validation for `configurable-root-and-keyboard-navigation`.
- [x] 6.2 Run targeted Swift tests for config, core input/model, CLI, control plane, and app shell changes.
- [x] 6.3 Run the repository verification command if targeted tests pass.
