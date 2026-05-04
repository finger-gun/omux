# OpenMUX Configuration and Themes

OpenMUX owns its user-facing configuration. Users edit **`~/.omux/config.toml`** and, optionally, add custom themes under **`~/.omux/themes/`**.

OpenMUX then compiles that config into an internal Ghostty config file under **`~/.omux/generated/ghostty/`** and applies it through the terminal bridge. OpenMUX does **not** read `~/.config/ghostty/config` by default.

New to OpenMUX? Start with [Getting started](./getting-started.md), then return here for the full configuration reference.

## Starter config

```toml
schema = 1

[theme]
name = "monokai-soda"

[terminal]
# font_family = "Berkeley Mono"
# font_size = 13
# scrollback_lines = 100000
# option_as_alt = "right"

[workspace]
default_root_path = "~"

[keys]
"cmd+n" = "workspace.create"
"cmd+shift+n" = "workspace.close"
"cmd+0" = "workspace.previous"
"cmd+ctrl+up" = "workspace.move-up"
"cmd+ctrl+down" = "workspace.move-down"
"cmd+1" = "workspace.focus-1"
"cmd+2" = "workspace.focus-2"
"cmd+3" = "workspace.focus-3"
"cmd+4" = "workspace.focus-4"
"cmd+5" = "workspace.focus-5"
"cmd+6" = "workspace.focus-6"
"cmd+7" = "workspace.focus-7"
"cmd+8" = "workspace.focus-8"
"cmd+9" = "workspace.focus-9"
"cmd+b" = "sidebar.toggle"
"cmd+d" = "pane.split-right"
"cmd+shift+d" = "pane.split-down"
"cmd+shift+w" = "pane.remove"
"ctrl+shift+tab" = "pane.next"
"cmd+t" = "pane-tab.create"
"cmd+w" = "pane-tab.close"
"ctrl+tab" = "pane-tab.next"

[ghostty]
# "copy-on-select" = false
```

## Token vocabulary

Themes are flat TOML files with a closed token set. Those tokens drive both the AppKit shell chrome and the Ghostty terminal colors.

| Token | AppKit role | Ghostty output |
| --- | --- | --- |
| `bg.canvas` | window canvas, terminal background | `background` |
| `bg.surface` | sidebar and supporting shell surfaces | — |
| `bg.elevated` | pane headers and compact shell actions | — |
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
- `atom-one-dark`
- `atom-one-light`
- `ayu`
- `ayu-light`
- `ayu-mirage`
- `carbonfox`
- `catppuccin`
- `catppuccin-frappe`
- `catppuccin-macchiato`
- `catppuccin-mocha`
- `cobalt2`
- `doom-one`
- `dracula`
- `duskfox`
- `everforest-dark`
- `fairyfloss`
- `firewatch`
- `flexoki-dark`
- `github-dark`
- `github-dark-dimmed`
- `github-dark-high-contrast`
- `github-light`
- `gruvbox`
- `gruvbox-dark-hard`
- `gruvbox-light-hard`
- `gruvbox-material-dark`
- `horizon`
- `kanagawa-wave`
- `material-darker`
- `material-ocean`
- `monokai-pro`
- `nightfox`
- `nord`
- `one-dark`
- `one-half-dark`
- `one-half-light`
- `onenord`
- `rose-pine`
- `snazzy`
- `solarized-dark`
- `solarized-light`
- `synthwave`
- `tokyo-night-storm`
- `tokyonight-moon`
- `tomorrow-night-eighties`
- `vesper`
- `wez`

The additional imported presets are generated from selected Ghostty-format themes in the [iTerm2 Color Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes) collection. Maintainers can refresh them with `make import-themes`, which uses `Scripts/theme-imports/iterm2-popular.txt` and the pinned ref in `Scripts/theme-imports/iterm2-colors-ref`.

## `[terminal]` settings

OpenMUX currently models these terminal settings directly:

| Key | Type | Meaning |
| --- | --- | --- |
| `font_family` | string | Preferred terminal font family. |
| `font_size` | integer | Terminal font size in points. |
| `scrollback_lines` | integer | Maximum scrollback preserved by the terminal. |
| `option_as_alt` | `false` \| `true` \| `"left"` \| `"right"` | OpenMUX-owned macOS Option-key behavior, compiled to Ghostty-compatible `macos-option-as-alt` semantics. |

Older configs may contain `keyboard_selection`; current OpenMUX ignores that deprecated key and removes it the next time `omux theme` rewrites the config.

### `terminal.option_as_alt`

`option_as_alt` controls which macOS Option key should behave like terminal Alt/Meta input.

Accepted values:

- `false` - keep Option text-producing unless the key chord produces no printable text
- `true` - treat both Option keys as Alt/Meta
- `"left"` - treat Left Option as Alt/Meta and keep Right Option text-producing
- `"right"` - treat Right Option as Alt/Meta and keep Left Option text-producing
- unset - use the default behavior

Example:

```toml
[terminal]
option_as_alt = "right"
```

Notes:

1. OpenMUX owns the user-facing setting, but the behavior is intentionally Ghostty-compatible.
2. OpenMUX does not hardcode Swedish, German, US, or other layout-specific Option character maps; text comes from AppKit for the active keyboard layout.
3. For manual verification of international layouts and IME workflows, see the contributor guidance in [`../CONTRIBUTING.md`](../CONTRIBUTING.md).

## `[workspace]` settings

OpenMUX currently models these workspace settings directly:

| Key | Type | Meaning |
| --- | --- | --- |
| `default_root_path` | string | Default workspace root used when OpenMUX opens a workspace without an explicit path. |

### `workspace.default_root_path`

`default_root_path` controls the root path used for first launch, new workspaces created from the app shell, and `omux open` when no path is provided.

Example:

```toml
[workspace]
default_root_path = "~/projects"
```

The path must resolve to an existing directory. `~` and `~/...` expand to the current user's home directory. If unset, OpenMUX uses the current user's home directory.

## `[keys]` keybindings

`[keys]` maps a single key chord to an OpenMUX shell action. Use it to resolve conflicts with terminal applications such as Helix, Vim, tmux, or remote SSH sessions: bind the action elsewhere, or map the chord to `"none"` so OpenMUX leaves it to the terminal.

Example:

```toml
[keys]
"cmd+shift+w" = "none"
"cmd+shift+p" = "pane.remove"
```

Chord syntax:

- Modifiers: `cmd`, `ctrl`, and `shift`.
- Keys: letters, digits, `tab`, `backspace`, `up`, and `down`.
- Chords are case-insensitive and serialized in normalized form such as `cmd+shift+w`.
- Option/Alt chords are rejected because Option and right-Option are commonly needed for international text input.

Supported action identifiers:

| Action | Meaning |
| --- | --- |
| `workspace.create` | Create a workspace. |
| `workspace.close` | Close/delete the active workspace. |
| `workspace.previous` | Focus the previously focused workspace. |
| `workspace.move-up` | Move the active workspace up. |
| `workspace.move-down` | Move the active workspace down. |
| `workspace.focus-1` ... `workspace.focus-9` | Focus a workspace by visible order. |
| `sidebar.toggle` | Toggle the workspace column. |
| `pane.split-right` | Split the focused pane to the right. |
| `pane.split-down` | Split the focused pane downward. |
| `pane.remove` | Remove the active pane. |
| `pane.next` | Focus the next visible pane. |
| `pane.previous` | Focus the previous visible pane. |
| `pane-tab.create` | Create a pane-local tab. |
| `pane-tab.close` | Close the active pane-local tab. |
| `pane-tab.next` | Focus the next pane-local tab. |
| `pane-tab.previous` | Focus the previous pane-local tab. |

Default bindings are generated by `omux config init`. Notably, OpenMUX does **not** bind `cmd+shift+backspace` by default; modified Backspace remains terminal-owned unless you explicitly bind it.

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
omux theme
omux theme <name>
omux theme list
omux list --full
omux sessions
omux panes
omux run --session <session-id> -- pwd
omux send-text --pane <pane-id> -- "hello"
```

When attached to an interactive terminal, `omux theme` opens a keyboard picker: use Up/Down to move, Enter to apply the highlighted theme, and `q` or Escape to cancel. In non-interactive contexts it keeps the scriptable prompt that accepts a typed theme number or name.

## Hooks

OpenMUX discovers executable user hooks under **`~/.omux/hooks/`**. See [Hooks](./hooks.md) for the full hook layout, payload contract, hook list, and examples.
