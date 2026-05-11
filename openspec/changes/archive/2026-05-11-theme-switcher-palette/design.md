## Context

The command palette is a keyboard-driven overlay that lists commands and workspaces. Currently it is a flat single-level list. Theme selection requires editing `~/.omux/config.toml` directly. The configuration coordinator owns theme persistence and already has a file-watch loop that triggers `onThemeChange` when the config file changes.

`WorkspaceShellTheme.availableThemes` returns all built-in and user themes. `WorkspaceWindowController.updateTheme(_:)` applies a theme live to all views without persisting anything.

## Goals / Non-Goals

**Goals:**
- "Switch Theme" command appears in the command palette command list
- Selecting it replaces the result list in-place with available themes (sub-palette mode)
- Browsing themes (arrow keys) triggers a live preview via `updateTheme`
- Confirming (Enter) persists the selection to `~/.omux/config.toml` and closes the palette
- Cancelling (ESC) reverts to the original theme, returns to the command list (not close)
- The currently active theme is visually distinguished with an accent checkmark
- Theme search/filter works the same as other palette results

**Non-Goals:**
- No theme creation or editing from within the palette
- No preview animation or transition effects
- No thumbnail/swatch rendering of theme colors

## Decisions

### Decision: Sub-palette as a mode on `CommandPaletteView`, not a separate view

The palette replaces `resultProvider` and sets a few extra callbacks when entering sub-palette mode, rather than pushing a new view. This keeps the existing layout, scroll, keyboard handling, and theme-application code intact. A `subPaletteMode` enum on `CommandPaletteView` tracks whether we are in top-level or sub-palette state.

**Alternative considered:** Push a new `CommandPaletteView` instance as a child. Rejected — doubles the view hierarchy and requires passing all the same theme/layout state again.

### Decision: Preview via existing `updateTheme` + revert on cancel

On entering theme sub-palette mode the controller snapshots `currentTheme`. Arrow key navigation calls `updateTheme` with the highlighted theme for live preview. ESC restores the snapshot. Confirmed selection persists and the snapshot is discarded.

This keeps preview entirely in memory — no partial writes to disk, no risk of leaving the config in an inconsistent state.

### Decision: Persist via a new `setTheme(identifier:)` on `OpenMUXConfigurationCoordinator`

The coordinator already owns the config file path and write logic. A new method reads the current config, mutates `theme.name`, writes it back, and then triggers the same `onThemeChange` path already used by file-watch reloads. This avoids any new persistence mechanism and reuses the existing coordinator lock.

**Alternative considered:** Write config directly from `WorkspaceWindowController`. Rejected — breaks the single-owner rule for config mutation.

### Decision: `isActive` flag on `CommandPaletteResult` rather than a separate indicator map

Adding `isActive: Bool` to `CommandPaletteResult` keeps the row self-contained. The result provider sets it based on `currentTheme.identifier == theme.identifier`. The row renders a small `checkmark` SF Symbol in the accent color when `isActive` is true.

### Decision: ESC in sub-palette returns to command list, not closes palette

One ESC exits sub-palette mode and reverts any preview. A second ESC closes the palette entirely. This matches the mental model of "going back" rather than "cancelling everything".

The `cancelOperation` handler in `CommandPaletteView` checks `subPaletteMode` and either exits sub-palette or dismisses.

## Risks / Trade-offs

- **Config write race**: If the file watcher fires between the coordinator reading and writing the config, the write could clobber an unrelated change. Mitigation: the coordinator already holds a lock around config mutations; the new method uses the same lock.
- **`availableThemes` is computed on every open**: Loading themes from disk on each sub-palette open adds a small latency. Mitigation: acceptable for now; `builtInPresets` is already cached as a static.
- **Revert latency**: Reverting on ESC calls `updateTheme` which re-applies all colors. On slow machines this could be perceptible. Mitigation: this is the same path used for normal theme changes; no extra work is introduced.
