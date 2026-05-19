# OpenMUX Configuration and Themes

OpenMUX owns its user-facing configuration. Users edit **`~/.omux/config.toml`** and, optionally, add custom themes under **`~/.omux/themes/`**.

OpenMUX then compiles that config into an internal Ghostty config file under **`~/.omux/generated/ghostty/`** and applies it through the terminal bridge. OpenMUX does **not** read `~/.config/ghostty/config` by default.

New to OpenMUX? Start with [Getting started](./getting-started.md), then return here for the full configuration reference.

Open the config file from the CLI:

```bash
omux config open
```

If you prefer a graphical editor, install the registry-hosted Settings UI plugin:

```bash
omux plugins install settings-ui
omux settings-ui
```

The Settings UI opens an extension pane, renders supported config keys with defaults, and saves through OpenMUX's config validation path.

## Starter config

```toml
schema = 1
# auto_check_update = true

[theme]
name = "monokai-soda"

[terminal]
# font_family = "Berkeley Mono"
# font_size = 13
# scrollback_lines = 100000
# option_as_alt = "right"
# persist_scrollback = true
# persist_scrollback_lines = 4000
# persist_scrollback_bytes = 1048576

[workspace]
default_root_path = "~"

[ui.panes]
# inactive_opacity = 0.5
# idle_status_clear = "on-focus"

[ui.icons]
# enabled = true
# provider = "nerd-font"
# colors_enabled = true
# font_family = "JetBrainsMono Nerd Font" # optional override; OpenMUX bundles Symbols Nerd Font Mono

[plugins.markdown-preview]
enabled = true
renderer = "builtin"
theme = "auto"

[registries]
hooks = ["https://github.com/finger-gun/omux-hooks"]
plugins = ["https://github.com/finger-gun/omux-plugins"]

[keys]
"cmd+p" = "command-palette.workspace"
"cmd+shift+p" = "command-palette.command"
"cmd+n" = "workspace.create"
"cmd+shift+n" = "workspace.close"
"cmd+0" = "workspace.previous"
"cmd+ctrl+shift+up" = "workspace.move-up"
"cmd+ctrl+shift+down" = "workspace.move-down"
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
"cmd+f" = "pane.find"
"ctrl+shift+tab" = "pane.next"
"cmd+ctrl+=" = "pane.resize-equalize"
"cmd+ctrl+up" = "pane.resize-up"
"cmd+ctrl+down" = "pane.resize-down"
"cmd+ctrl+left" = "pane.resize-left"
"cmd+ctrl+right" = "pane.resize-right"
"cmd+t" = "pane-tab.create"
"cmd+w" = "pane-tab.close"
"ctrl+tab" = "pane-tab.next"

[ghostty]
# "copy-on-select" = false
```

## Root settings

| Key | Type | Meaning |
| --- | --- | --- |
| `schema` | integer | Required config schema version. |
| `auto_check_update` | boolean | Enables passive background checks for newer OpenMUX GitHub Releases. Defaults to `true`; set to `false` to opt out. |

Update checks run in the background after app startup. Failed checks do not show user-facing errors.

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
- `banana-blueberry`
- `borland`
- `c64`
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
- `grass`
- `gruvbox`
- `gruvbox-dark-hard`
- `gruvbox-light-hard`
- `gruvbox-material-dark`
- `hot-dog-stand`
- `horizon`
- `kanagawa-wave`
- `laser`
- `man-page`
- `material-darker`
- `material-ocean`
- `matrix`
- `monokai-pro`
- `nightfox`
- `nord`
- `one-dark`
- `one-half-dark`
- `one-half-light`
- `onenord`
- `red-sands`
- `rose-pine`
- `snazzy`
- `solarized-dark`
- `solarized-light`
- `synthwave`
- `tokyo-night-storm`
- `tokyonight-moon`
- `tomorrow-night-eighties`
- `under-the-sea`
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
| `persist_scrollback` | boolean | Enables OpenMUX persisted pane scrollback across app restarts. Defaults to `true`. |
| `persist_scrollback_lines` | integer | Maximum lines of per-pane scrollback OpenMUX persists for restart restore. Defaults to `4000`. |
| `persist_scrollback_bytes` | integer | Maximum bytes of per-pane scrollback OpenMUX persists for restart restore. Defaults to `1048576`. |

Older configs may contain `keyboard_selection`; current OpenMUX ignores that deprecated key and removes it the next time `omux theme` rewrites the config.

### Persisted scrollback

OpenMUX persists bounded per-pane scrollback locally so restored workspaces can show useful terminal history after app restart. This is best-effort history: OpenMUX starts a fresh shell and does not restore running commands, SSH connections, TUI processes, or exact scroll position.

Persisted scrollback is enabled by default and stored only in OpenMUX-managed local persistence under `~/Library/Application Support/OpenMUX/`. Workspace state is stored as JSON, while larger scrollback payloads are stored separately so terminal history does not live in `UserDefaults`.

OpenMUX stores and replays raw terminal output where safe, including ANSI color and styling sequences. On restore, OpenMUX replays the saved output before the fresh shell prompt appears, then resets terminal formatting before starting the shell. Full-screen terminal apps such as Vim, less, htop, and other alternate-screen TUIs are handled as best-effort history only; OpenMUX does not resume their process state.

Because terminal output can contain secrets, set `persist_scrollback = false` to opt out.

Use `omux history clear` to remove persisted scrollback for all panes and clear live screen/scrollback for currently running panes when available. When the command runs inside an OpenMUX-launched pane, the CLI also clears that pane's terminal buffer locally after the control-plane clear succeeds. Scope cleanup with `--pane <id>`, `--pane-tab <id>`, `--tab <id>`, `--workspace <id>`, `--session <id>`, or `--focused` when only part of the restored history should be cleared.

Example:

```toml
[terminal]
persist_scrollback = true
persist_scrollback_lines = 4000
persist_scrollback_bytes = 1048576
```

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

## Agent Sessions settings

Agent Sessions indexes local coding-agent history so OpenMUX can search, resume, and show activity for sessions in the sidebar. See [Agent Sessions](./agent-sessions.md) for the user workflow and architecture diagrams.

```toml
[agent-sessions]
enabled = true
preview_enabled = true
index_on_launch = true
included_agents = ["copilot", "codex", "gemini"]
excluded_paths = []
max_preview_bytes = 1048576
sidebar_rows_per_agent = 10

[agent-sessions.agents.copilot]
home = "~/.copilot"
resume_command = "copilot --resume {session_id}"
```

| Key | Type | Meaning |
| --- | --- | --- |
| `enabled` | boolean | Shows Agent Sessions UI and enables indexing. Defaults to `true`. |
| `preview_enabled` | boolean | Reserved for preview-capable Agent Sessions surfaces. Defaults to `true`. |
| `index_on_launch` | boolean | Rebuilds the local index when OpenMUX starts. Defaults to `true`. |
| `included_agents` | array of strings | Agents to index. Common values are `copilot`, `codex`, `gemini`, `claude`, `opencode`, `pi`, and `rovodev`. |
| `excluded_paths` | array of strings | Paths to skip while indexing. |
| `max_preview_bytes` | integer | Reserved maximum preview payload size. |
| `sidebar_rows_per_agent` | integer | Number of rows to fetch per agent for each sidebar page. Defaults to `10`. |

Per-agent tables live under `[agent-sessions.agents.<agent>]`:

| Key | Type | Meaning |
| --- | --- | --- |
| `enabled` | boolean | Include or exclude this agent without replacing the whole `included_agents` list. |
| `home` | string | Override the agent's local home directory. |
| `resume_command` | string | Resume command template. `{session_id}` is replaced with a shell-quoted raw session ID. |

## `[plugins]` settings

Bundled plugins are configured under `[plugins.<name>]`. Use `omux plugins` for the interactive fuzzy-search picker that can toggle configurable bundled plugins.

For the plugin ecosystem and extension-pane contract, see [Plugin ecosystem](./plugins.md). For bundled plugin user docs, see [Plugin index](./plugins/index.md).

### `[plugins.markdown-preview]`

The bundled Markdown Preview plugin is enabled by default. It demonstrates extension panes by rendering local Markdown to constrained local HTML and asking the control plane to open or update a neighboring pane.

| Key | Type | Meaning |
| --- | --- | --- |
| `enabled` | boolean | Enables the bundled `omux markdown-preview` command and terminal-path activation. Defaults to `true`. |
| `renderer` | `"builtin"` | Selects the built-in Markdown renderer. |
| `theme` | `"auto"` \| `"light"` \| `"dark"` | Chooses preview colors. `auto` follows the system color scheme. |

Example:

```toml
[plugins.markdown-preview]
enabled = true
renderer = "builtin"
theme = "auto"
```

Run `omux markdown-preview README.md --watch` from an OpenMUX pane to open a preview beside your terminal. See [Markdown Preview plugin](./plugins/markdown-preview.md) for the full workflow.

## `[registries]` settings

Extension registry URLs configure where `omux hooks` and `omux plugins` discover remote packages. Official registries are used by default.

| Key | Type | Meaning |
| --- | --- | --- |
| `hooks` | array of URL strings | Hook registries used by `omux hooks discover/install`. Defaults to `https://github.com/finger-gun/omux-hooks`. |
| `plugins` | array of URL strings | Plugin registries used by `omux plugins discover/install`. Defaults to `https://github.com/finger-gun/omux-plugins`. |

Example:

```toml
[registries]
hooks = ["https://github.com/finger-gun/omux-hooks"]
plugins = ["https://github.com/finger-gun/omux-plugins", "https://github.com/example/omux-plugins"]
```

Use `--registry <url>` on a discover or install command to override configured registries for one invocation.

Registry installs copy package files into `~/.omux/hooks/` or `~/.omux/plugins/` and write receipts under `~/.omux/installed/`. OpenMUX does not fetch remote code while running hooks or plugins; installed executable files run locally.

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

## `[ui.panes]` settings

| Key | Type | Meaning |
| --- | --- | --- |
| `inactive_opacity` | number from `0.0` to `1.0` | Opacity for inactive pane cards. Defaults to `0.5`; set to `1.0` to disable dimming. |
| `idle_status_clear` | `"on-focus"`, `"after-delay"`, or `"never"` | Controls when an idle status orb is removed after a pane reports idle/completed status. Defaults to `"on-focus"` so background panes keep their orb until you focus them. |

Set it from the CLI with:

```bash
omux config inactive-opacity 0.7
```

## `[ui.icons]` settings

OpenMUX can show lightweight project/session icons in workspace rows, terminal rows, and pane tabs. Icons are decorative context; the text title remains the primary identifier.

| Key | Type | Meaning |
| --- | --- | --- |
| `enabled` | boolean | Enables semantic icons. Defaults to `true`. |
| `provider` | `"nerd-font"` \| `"sf-symbols"` \| `"text"` | Preferred icon rendering provider. Defaults to `"nerd-font"`. |
| `colors_enabled` | boolean | Tints icons from semantic theme colors. Defaults to `true`; set to `false` to use normal label colors. |
| `font_family` | string | Optional Nerd Font family override for icon glyphs. |

The Nerd Font provider uses a bundled `Symbols Nerd Font Mono` resource for common developer contexts such as Node, Swift, Rust, Go, Python, Docker, Git, terminal, workspace, AI/Copilot sessions, and common terminal apps such as Helix, Vim, Neovim, tmux, and SSH. Users do not need to install Nerd Fonts separately. Icons are tinted from the active theme's ANSI palette, such as green for Node/editors, cyan for Docker/Go/SSH, red for Git/Rust/Swift, and magenta for AI sessions, with contrast-safe fallback on selected rows. Set `colors_enabled = false` to keep icons in the same color as surrounding labels. Set `font_family` only if you want OpenMUX to prefer another installed Nerd Font; if that font cannot render a glyph, OpenMUX falls back to the bundled font and then to simple text/SF Symbol-style representations so the UI remains readable. The bundled Nerd Fonts Symbols Only license is included with the app resources.

Example:

```toml
[ui.icons]
enabled = true
provider = "nerd-font"
colors_enabled = true
# font_family = "JetBrainsMono Nerd Font"
```

## `[keys]` keybindings

`[keys]` maps a single key chord to an OpenMUX shell action. User action bindings replace OpenMUX defaults for that action, so rebinding only requires the new chord. Use `"none"` when you want OpenMUX to leave a chord to the terminal.

The command palette is the keyboard-first shell entrypoint. `Cmd+P` opens workspace search with all open workspaces listed. `Cmd+Shift+P` opens the same palette with `>` prefilled for OpenMUX actions and the full `omux` command catalog. While the palette is open, query text stays in the palette and is not sent to the focused terminal until a command is invoked.

Command-mode action entries are backed by bundled JSON descriptors with a typed `command.kind` and `command.target`; CLI entries are generated from the shared CLI command catalog. Invoking a CLI entry routes its `omux ...` command through the focused terminal, submitting commands without required arguments and inserting editable templates for commands that need arguments.

Example:

```toml
[keys]
"cmd+shift+p" = "pane.remove"
"cmd+shift+w" = "none"
```

Chord syntax:

- Modifiers: `cmd`, `ctrl`, and `shift`.
- Keys: letters, digits, `tab`, `backspace`, `up`, `down`, `left`, `right`, and `=`.
- Chords are case-insensitive and serialized in normalized form such as `cmd+shift+w`.
- Option/Alt chords are rejected because Option and right-Option are commonly needed for international text input.

Supported action identifiers:

| Action | Meaning |
| --- | --- |
| `command-palette.workspace` | Open the command palette in workspace search mode. |
| `command-palette.command` | Open the command palette in command search mode with `>` prefilled. |
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
| `pane.resize-equalize` | Equalize split sizes in the active tab. |
| `pane.resize-up` | Move the active split divider up. |
| `pane.resize-down` | Move the active split divider down. |
| `pane.resize-left` | Move the active split divider left. |
| `pane.resize-right` | Move the active split divider right. |
| `pane-tab.create` | Create a pane-local tab. |
| `pane-tab.close` | Close the active pane-local tab. |
| `pane-tab.next` | Focus the next pane-local tab. |
| `pane-tab.previous` | Focus the previous pane-local tab. |

Default bindings are generated by `omux config init`. In the palette, a first-character `>` switches to command search; whitespace before `>` remains workspace search text. Notably, OpenMUX does **not** bind `cmd+shift+backspace` by default; modified Backspace remains terminal-owned unless you explicitly bind it.

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
omux config open
omux config reload
omux config get --json
omux config apply --json-file /path/to/payload.json
omux config init
omux theme
omux theme <name>
omux theme list
omux plugins
omux plugin list
omux plugin path
omux list --full
omux sessions
omux panes
omux run --session <session-id> -- pwd
omux send-text --pane <pane-id> -- "hello"
```

When attached to an interactive terminal, `omux theme` opens a keyboard picker: type to fuzzy-filter by theme id or display name, use Up/Down to move, Enter to apply the highlighted theme, Backspace to edit the filter, and Escape to cancel. For example, typing `cat` narrows the list to the Catppuccin themes. In non-interactive contexts it keeps the scriptable prompt that accepts a typed theme number or name.

When attached to an interactive terminal, `omux plugins` opens a similar picker for bundled plugin toggles.

`omux config get --json` and `omux config apply --json-file` are primarily for tools and plugins. They expose supported OpenMUX-owned settings, defaults, diagnostics, atomic apply behavior, backups, and app reload on success.

## Hooks

OpenMUX discovers executable user hooks under **`~/.omux/hooks/`**. See [Hooks](./hooks.md) for the full hook layout, payload contract, hook list, and examples.
