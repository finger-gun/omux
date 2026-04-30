# import-iterm2

Dev-time importer for turning `.itermcolors` palettes into fully-populated OpenMUX theme TOML files.

## Usage

```bash
swift Scripts/import-iterm2.swift path/to/theme.itermcolors Sources/OmuxTheme/Resources/themes/my-theme.toml --name my-theme --display-name "My Theme"
```

## What it does

1. Reads the iTerm2 plist.
2. Extracts:
   - background
   - foreground
   - cursor
   - selection
   - ANSI 0-15 colors
3. Derives the extra OpenMUX chrome tokens that iTerm2 palettes do not define:
   - `bg.surface`
   - `bg.elevated`
   - `fg.secondary`
   - `fg.muted`
   - `border.subtle`
   - `border.strong`
   - `accent`
4. Writes a flat OpenMUX theme TOML file with the full token set.

## Workflow

The importer is intentionally **not** a runtime feature. Use it to bootstrap or refresh built-in themes, then review the generated TOML and hand-tune any chrome tokens that look off before committing.

Typical flow:

```bash
swift Scripts/import-iterm2.swift ./Downloads/Dracula.itermcolors /tmp/dracula.toml --name dracula --display-name "Dracula"
diff -u /tmp/dracula.toml Sources/OmuxTheme/Resources/themes/dracula.toml
```

## Notes

- Theme derivation here is an **import heuristic**, not the runtime theme system.
- Runtime OpenMUX themes stay flat and fully specified.
- If a palette has a stronger identity color than ANSI blue, override `accent` manually after import.
