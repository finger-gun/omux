# OpenMUX Configuration and Themes

OpenMUX owns its user-facing configuration. Users edit **`~/.omux/config.toml`** and, optionally, add custom themes under **`~/.omux/themes/`**.

OpenMUX then compiles that config into an internal Ghostty config file under **`~/.omux/generated/ghostty/`** and applies it through the terminal bridge. OpenMUX does **not** read `~/.config/ghostty/config` by default.

## Starter config

```toml
schema = 1

[theme]
name = "monokai-soda"

[terminal]
# font_family = "Berkeley Mono"
# font_size = 13
# scrollback_lines = 100000

[ghostty]
# "copy-on-select" = false
```

## Token vocabulary

Themes are flat TOML files with a closed token set. Those tokens drive both the AppKit shell chrome and the Ghostty terminal colors.

| Token | AppKit role | Ghostty output |
| --- | --- | --- |
| `bg.canvas` | window canvas, terminal background | `background` |
| `bg.surface` | sidebar, top bar, pane cards | — |
| `bg.elevated` | pane headers, pill/button base | — |
| `fg.primary` | primary labels | `foreground` |
| `fg.secondary` | secondary labels | — |
| `fg.muted` | section labels, subdued copy | — |
| `border.subtle` | quiet strokes | — |
| `border.strong` | stronger card/frame strokes | — |
| `accent` | focus and active accents | — |
| `cursor` | terminal cursor | `cursor-color` |
| `cursor.text` | cursor text contrast | `cursor-text` |
| `selection.bg` | selection / active chrome tint | `selection-background` |
| `selection.fg` | terminal selection foreground | `selection-foreground` |
| `ansi.black` | terminal ANSI 0 | `palette = 0=...` |
| `ansi.red` | terminal ANSI 1 | `palette = 1=...` |
| `ansi.green` | terminal ANSI 2 | `palette = 2=...` |
| `ansi.yellow` | terminal ANSI 3 | `palette = 3=...` |
| `ansi.blue` | terminal ANSI 4 | `palette = 4=...` |
| `ansi.magenta` | terminal ANSI 5 | `palette = 5=...` |
| `ansi.cyan` | terminal ANSI 6 | `palette = 6=...` |
| `ansi.white` | terminal ANSI 7 | `palette = 7=...` |
| `ansi.brightBlack` | terminal ANSI 8 | `palette = 8=...` |
| `ansi.brightRed` | terminal ANSI 9 | `palette = 9=...` |
| `ansi.brightGreen` | terminal ANSI 10 | `palette = 10=...` |
| `ansi.brightYellow` | terminal ANSI 11 | `palette = 11=...` |
| `ansi.brightBlue` | terminal ANSI 12 | `palette = 12=...` |
| `ansi.brightMagenta` | terminal ANSI 13 | `palette = 13=...` |
| `ansi.brightCyan` | terminal ANSI 14 | `palette = 14=...` |
| `ansi.brightWhite` | terminal ANSI 15 | `palette = 15=...` |

## Built-in themes

OpenMUX currently ships:

- `monokai-soda`
- `catppuccin`
- `dracula`
- `nord`
- `gruvbox`
- `one-dark`
- `solarized-dark`
- `solarized-light`

## `[ghostty]` pass-through

`[ghostty]` is the advanced escape hatch for keys OpenMUX does not model yet.

Example:

```toml
[ghostty]
"copy-on-select" = false
"font-feature" = ["-calt"]
```

Rules:

1. OpenMUX writes `[ghostty]` entries first, then writes OpenMUX-managed keys last.
2. If a pass-through key collides with an OpenMUX-managed key, **OpenMUX wins** and a warning is emitted.
3. Pass-through keys are not versioned as part of the stable OpenMUX user API.
4. The pass-through is intentionally broad; it exists for terminal-engine escape hatches, not as the primary config surface.

## CLI

Use the running app’s control plane for diagnostics and explicit reloads:

```bash
omux config doctor
omux config reload
omux config init
```
