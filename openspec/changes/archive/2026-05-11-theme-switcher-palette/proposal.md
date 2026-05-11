## Why

Switching themes currently requires manually editing `~/.omux/config.toml`, saving, and waiting for the file watcher to reload — there is no interactive way to browse and preview themes from within the running app. A command palette–driven theme switcher gives developers an immediate, keyboard-first way to discover, preview, and apply themes without leaving the terminal workspace.

## What Changes

- Add a "Switch Theme" entry to the command palette command catalog
- Extend `CommandPaletteView` with a sub-palette mode for browsing a secondary result list
- Add live-preview and revert callbacks to `CommandPaletteView` so the palette can drive theme changes without persisting them
- Add `setTheme(identifier:)` to `OpenMUXConfigurationCoordinator` to persist the selected theme to `~/.omux/config.toml`
- Extend `CommandPaletteResult` with an `isActive` flag so the currently active theme can be visually indicated in the result row
- Update `CommandPaletteResultRow` to render an active-state indicator (accent-colored checkmark) when `isActive` is true

## Capabilities

### New Capabilities
- `command-palette-sub-palette`: The ability for the command palette to replace its result list with a secondary contextual list in response to a command selection, with preview, confirm, and cancel semantics distinct from the top-level palette dismiss.

### Modified Capabilities
- `theme-system`: Theme apply-live requirement now also covers programmatic theme selection from within the app shell (not only config-file edits and reloads).

## Impact

- `CommandPaletteView.swift` — new sub-palette mode, preview/commit/revert callback hooks
- `CommandPaletteResult` (OmuxCore) — new `isActive: Bool` field
- `CommandPaletteResultRow` — active indicator rendering
- `CommandPaletteCommands.swift` — new "Switch Theme" command descriptor wired to a new invocation target or handled inline
- `OpenMUXConfigurationCoordinator.swift` — new `setTheme(identifier:)` that mutates and writes `~/.omux/config.toml`
- `WorkspaceWindowController.swift` — wires preview and commit callbacks when presenting the palette
- No changes to the libghostty bridge boundary
- No new background services or daemons
