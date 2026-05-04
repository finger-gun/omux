## Why

Users can see terminal/pane-tab rows in the workspace sidebar, but clicking those rows does not reliably activate the corresponding pane tab when it is outside the currently active workspace. That makes visible terminal navigation feel non-direct in a terminal-first workspace where pane/session focus should be obvious and fast.

The View menu has also accumulated workspace, pane, pane-tab, and visual chrome actions. Splitting model-level actions into Workspace and Pane menus keeps OpenMUX-native concepts discoverable without overloading View with non-view commands.

## What Changes

- Make sidebar terminal metadata rows directly focus the clicked pane tab, including pane tabs in inactive workspaces.
- Preserve the existing shared pane-tab focus action/event path so sidebar clicks, CLI/control-plane focus, and pane-tab chrome stay consistent.
- Split current workspace and pane actions out of the View menu into top-level Workspace and Pane menus.
- Keep View for visual shell/chrome toggles such as the workspace column.
- Preserve existing keybindings and validation behavior after moving menu items.
- No breaking CLI, RPC, hook, or persistence changes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pane-tab-stacks`: Direct pane-tab focus shall work from visible sidebar terminal rows, including rows for inactive workspaces.
- `sidebar-terminal-metadata`: Terminal metadata rows shall behave as actionable navigation targets, not just status display.
- `macos-app-shell`: The app menu structure shall separate Workspace, Pane, and View responsibilities while preserving shortcuts and validation.

## Impact

- Affected code includes `WorkspaceController`, `WorkspaceWindowController`, `OpenMUXAppDelegate`, and related AppKit tests.
- The change is AppKit shell/UI only; it does not affect the libghostty bridge boundary, terminal rendering, PTY behavior, keyboard input encoding, hooks, plugin APIs, or JSON-RPC method names.
- Keyboard correctness is not changed. Existing shortcut bindings remain sourced from the keybinding registry and continue to use AppKit menu equivalents.
