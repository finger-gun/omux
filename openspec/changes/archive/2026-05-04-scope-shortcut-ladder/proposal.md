## Why

After assigning `Cmd+W` to close the focused pane-local tab, deleting a workspace no longer has a fast keyboard path. Pane removal also needs a discoverable shortcut that does not rely on Backspace. The shell should provide explicit destructive shortcuts for panes and workspaces without replacing the existing pane split shortcuts.

CLI automation should have the same coverage as native shortcuts so users and tools can create/remove workspaces, panes, and pane tabs without relying on UI-only actions.

## Goals

- Add a keyboard shortcut for deleting/closing the active workspace.
- Add a mnemonic pane remove shortcut while preserving existing pane split shortcuts.
- Preserve existing shortcuts and commands so current workflows keep working.
- Add missing CLI/control-plane parity for workspace close/delete and pane remove.
- Keep the shortcut set explicit and safe for international keyboard layouts.

## Non-goals

- Do not remove existing `Cmd+D`, `Cmd+Shift+D`, or pane-tab shortcuts.
- Do not introduce Option-based shortcuts because Option/right-Option is important for international text input.
- Do not change pane-tab CLI commands that already exist.
- Do not add modal keybinding configuration in this change.

## What Changes

- Add `Cmd+Shift+W` as a new native shortcut for removing the active pane.
- Keep existing pane split shortcuts (`Cmd+D`, `Cmd+Shift+D`) and remove the old pane remove shortcut (`Cmd+Shift+Backspace`).
- Add `Cmd+Shift+N` as the native shortcut for deleting/closing the active workspace while keeping `Cmd+N` for creating a workspace.
- Add missing control-plane and CLI actions for closing workspaces and removing panes:
  - `workspace.close`
  - `pane.remove`
  - `omux workspace-close [workspace-id]`
  - `omux pane-remove [target]`
- Preserve existing CLI commands including `omux open`, `omux split`, `omux pane-tab`, and `omux pane-tab-close`.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `input-pipeline`: Add explicit allowlisted shortcuts for scoped destructive actions without broadening terminal input interception.
- `macos-app-shell`: Add native menu/key command bindings for workspace close and pane remove.
- `workspace-session-actions`: Extend shared actions to cover workspace close and pane remove parity.
- `omux-control-plane`: Add JSON-RPC and CLI automation contracts for workspace close and pane remove.

## Impact

- Affected code: AppKit menu configuration, input shortcut classifier, control-plane method enum/handlers, CLI command parser, workspace controller action responses, tests.
- APIs: additive JSON-RPC methods and CLI commands; no breaking changes.
- Keyboard/input: Command-only and Command+Shift shortcuts remain explicit allowlist entries; Option/right-Option and composition input remain terminal-owned.
- Terminal bridge: no `libghostty` bridge changes; pane/workspace structure remains OpenMUX shell state.
