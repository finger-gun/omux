## Why

OpenMUX currently opens first-launch and sidebar-created workspaces from the app process working directory, which can resolve to `/` and produces a poor terminal-first default. Pane-local tabs and pane navigation also exist in the model but are not consistently available through keyboard and CLI workflows, making keyboard-driven workspace control incomplete.

This change makes workspace startup location predictable and configurable, and makes pane-local tab/pane navigation available through shared shell and automation commands.

## Goals

- Let users configure the default workspace root used by first launch, sidebar/menu workspace creation, and `omux open` without an explicit path.
- Keep explicit `omux open <path>` behavior available for opening a specific workspace root.
- Add native key commands for creating, closing, and cycling pane-local tabs, and for cycling panes in the current workspace.
- Add CLI and control-plane parity for all new navigation actions so hooks and scripts can invoke the same capabilities.
- Preserve terminal input correctness by only intercepting explicit OpenMUX shortcuts.

## Non-goals

- Do not introduce a browser-heavy workspace picker or project database.
- Do not add a background indexing service for recent projects.
- Do not change the libghostty bridge boundary or expose terminal-engine types through workspace/navigation APIs.
- Do not replace existing workspace number shortcuts: `Cmd+1` through `Cmd+9` continue to jump to visible workspaces and `Cmd+0` continues to recall the previous workspace.

## What Changes

- Add a `[workspace] default_root_path` OpenMUX config setting, defaulting to the user's home directory.
- Resolve missing workspace-open paths through the configured default root for app startup, sidebar/menu-created workspaces, control-plane open requests, and `omux open`.
- Update `omux open <path>` to accept an optional path while preserving explicit path behavior.
- Add pane-local tab shortcuts:
  - New pane-local tab: `Cmd+T`
  - Close focused pane-local tab: `Cmd+W`
  - Cycle to next pane-local tab in the focused pane stack: `Ctrl+Tab`
- Add pane focus cycling:
  - Cycle to the next pane in visible layout order within the current workspace tab: `Ctrl+Shift+Tab`
- Add CLI/control-plane operations for next/previous pane-local tab focus and next/previous pane focus.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `config-system`: Add the workspace default root setting and validation.
- `workspace-session-actions`: Define default-root path resolution and shared pane/pane-tab navigation actions across UI and CLI.
- `pane-tab-stacks`: Add keyboard and automation requirements for creating, closing, and cycling pane-local tabs.
- `input-pipeline`: Extend the explicit shortcut allowlist for pane-tab and pane navigation chords without broad Control-key interception.
- `omux-control-plane`: Add capability-oriented RPC methods for pane-tab and pane focus cycling.

## Impact

- Affected modules: `OmuxConfig`, `OmuxAppShell`, `OmuxControlPlane`, `OmuxCLI`, `OmuxCore`, and documentation.
- Affected user surfaces: `~/.omux/config.toml`, `omux open`, pane-tab CLI commands, app menus, and keyboard shortcuts.
- Affected tests: config loading/diagnostics, CLI command routing, app shell workspace defaults/navigation, core input shortcut classification, and control-plane request handling.
- The libghostty boundary remains unchanged; navigation is modeled entirely in OpenMUX-native workspace, pane stack, pane, and session terms.
- Keyboard correctness is impacted intentionally: only exact OpenMUX-owned chords are intercepted, while Option/Alt text input, dead keys, compose/IME flows, and unclaimed Control or Command chords remain terminal-owned.
