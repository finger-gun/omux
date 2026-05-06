# OpenMUX Plugins and Extension Panes

OpenMUX plugins are external, scriptable integrations first. They talk to the same public `omux` CLI and JSON-RPC control plane that users can automate from shell scripts. Extension panes let those integrations place non-terminal content beside terminals without leaking terminal-engine details into plugin code.

## Register a CLI plugin command

User plugins register top-level `omux` commands by installing executables under `~/.omux/plugins/`.

For a single-file plugin, make the file executable:

```sh
mkdir -p ~/.omux/plugins
cp ./my-preview ~/.omux/plugins/my-preview
chmod +x ~/.omux/plugins/my-preview
omux my-preview --help
```

For a plugin that needs bundled files, use a directory with an executable named `plugin`:

```sh
mkdir -p ~/.omux/plugins/my-preview
cp ./run.sh ~/.omux/plugins/my-preview/plugin
chmod +x ~/.omux/plugins/my-preview/plugin
omux my-preview README.md
```

Built-in `omux` commands always take precedence, so a plugin cannot shadow commands such as `config`, `theme`, `history`, or `extension-pane`. Bundled plugins also register commands through this registry; for example, Markdown preview registers `omux markdown-preview`, and an external plugin cannot replace it by using the same command name.

Inspect registered plugins with:

```sh
omux plugin path
omux plugin list
```

When OpenMUX runs a plugin, it passes the remaining CLI arguments through unchanged and adds these environment variables:

| Variable | Meaning |
| --- | --- |
| `OMUX_PLUGIN_COMMAND` | Command name the user invoked. |
| `OMUX_PLUGIN_EXECUTABLE` | Absolute path to the executable OpenMUX launched. |
| `OMUX_PLUGINS_DIR` | Directory containing the plugin executable. |

Plugins can call back into `omux extension-pane`, `omux notify`, and other public commands to interact with the running app.

## Extension pane CLI contract

Use `omux extension-pane` to create, update, and close plugin-owned panes:

```sh
omux extension-pane create --plugin dev.example.preview --title "Preview" --source ./README.md --html-file /tmp/preview.html
omux extension-pane update --pane <pane-id> --plugin dev.example.preview --status ready --html-file /tmp/preview.html
omux extension-pane update --pane <pane-id> --plugin dev.example.preview --status error --message "render failed"
omux extension-pane close --pane <pane-id>
```

The control plane accepts these fields:

| Field | Meaning |
| --- | --- |
| `--plugin <id>` | Stable plugin identifier. Required for create and update. |
| `--pane <id>` | Existing extension pane to update or close. |
| `--title <title>` | User-facing pane title. |
| `--source <path>` | Local source path represented by the pane. |
| `--html <html>` / `--html-file <path>` | Local HTML content for the shell-owned preview host. |
| `--status ready\|disabled\|error` | Rendering state. Non-ready states show placeholder copy. |
| `--message <text>` | Placeholder or error message. |
| `--axis columns\|rows` | Split direction for new panes. |

Extension panes are shell-owned content panes. They are not terminal sessions, do not allocate Ghostty surfaces, and terminal-only actions such as `omux run`, `send-text`, and history operations reject or ignore them.

## Markdown preview workflow

Enable the bundled Markdown preview plugin:

```toml
[plugins.markdown-preview]
enabled = true
renderer = "builtin"
theme = "auto"
```

Then open a Markdown file from an OpenMUX terminal pane:

```sh
omux markdown-preview README.md --watch
```

The command renders the file to safe local preview HTML, opens an extension pane beside the current terminal, and keeps updating the preview while it runs. This fits editor workflows such as opening `README.md` in Helix in one pane and running the preview watcher in the neighboring pane.

To reuse an existing preview pane, pass its pane ID:

```sh
omux markdown-preview README.md --pane <pane-id> --watch
```

The built-in renderer escapes raw HTML and script content before it reaches the preview host. Links open externally, and the preview host disables JavaScript.
