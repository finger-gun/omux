# Markdown Preview Plugin

Markdown Preview is a bundled OpenMUX plugin for rendering local Markdown files in a neighboring extension pane. It is designed for terminal editor workflows: edit in Helix, Vim, Neovim, or another terminal editor, and keep the rendered preview beside it.

## Status and configuration

Markdown Preview is enabled by default.

```toml
[plugins.markdown-preview]
enabled = true
renderer = "builtin"
theme = "auto"
```

Set `enabled = false` to disable the `omux markdown-preview` command and Command-click Markdown path activation.

| Key | Type | Meaning |
| --- | --- | --- |
| `enabled` | boolean | Enables the bundled preview command and terminal-path activation. Defaults to `true`. |
| `renderer` | `"builtin"` | Selects the built-in Markdown renderer. |
| `theme` | `"auto"` \| `"light"` \| `"dark"` | Chooses preview colors. `auto` follows the system color scheme. |

Use the interactive plugin picker to toggle it:

```sh
omux plugins
```

## Open a preview

From an OpenMUX terminal pane:

```sh
omux markdown-preview README.md --watch
```

The command renders the file to local HTML, opens an extension pane beside the current terminal, and updates the pane when the file changes.

To reuse an existing preview pane:

```sh
omux markdown-preview README.md --pane <pane-id> --watch
```

You can also choose the split direction:

```sh
omux markdown-preview README.md --axis rows
```

## Command-click activation

When Markdown Preview is enabled, Command-clicking a readable local `.md` or `.markdown` path in terminal text opens or updates a preview pane for that file.
Those click-opened previews keep watching the source file and rerender automatically.

Examples that can be activated:

```text
README.md
docs/getting-started.md
./CHANGELOG.md:42
```

Paths resolve relative to the terminal pane's current working directory when possible. Plain clicks remain terminal-owned for focus, selection, and TUI mouse reporting.

## Rendering behavior

The built-in renderer supports GitHub Flavored Markdown-compatible features such as:

- tables
- task lists
- strikethrough
- autolinks
- fenced code blocks
- common raw HTML used in README files

Relative local image paths are resolved from the Markdown file's directory so README assets can render in the preview. Remote image URLs also work.

The preview host disables JavaScript. Before content reaches the host, the renderer strips script blocks, script-oriented attributes, and unsafe script URL schemes. Links open externally instead of turning the preview pane into a browser.

## Troubleshooting

If a preview does not open:

1. Run `omux config doctor` and fix any config diagnostics.
2. Confirm the plugin is enabled with `omux plugins` or by checking `[plugins.markdown-preview]`.
3. Confirm the file exists, is readable, and has a `.md` or `.markdown` extension for Command-click activation.
4. For watch mode, keep the `omux markdown-preview ... --watch` process running in a terminal pane.
