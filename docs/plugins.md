# OpenMUX Plugin Ecosystem

OpenMUX plugins are external, scriptable integrations first. They use the same public `omux` CLI and local JSON-RPC control plane that users can automate from shell scripts. This keeps plugin code outside the terminal engine and lets OpenMUX stay terminal-first.

For bundled plugin user docs, see the [plugin index](./plugins/index.md).

## What plugins can do

Plugins can:

- register top-level `omux` commands
- create, update, and close extension panes
- mark terminal pane status with `omux pane-status`
- call any public `omux` command
- react to hooks and terminal text activation events
- use their own runtime through a shebang or native executable

Plugins should not depend on AppKit objects, Ghostty types, or private OpenMUX internals. Stable boundaries are the CLI, JSON-RPC control plane, hooks, and extension-pane descriptors.

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

Built-in `omux` commands always take precedence, so a plugin cannot shadow commands such as `config`, `theme`, `history`, or `extension-pane`. Bundled plugins also reserve their command names through this registry; see the [plugin index](./plugins/index.md) for the current bundled list.

Inspect registered plugins with:

```sh
omux plugin path
omux plugin list
omux plugins
```

`omux plugins` opens an interactive picker with fuzzy search. Press Enter on a configurable bundled plugin to toggle it enabled or disabled. External executable plugins are listed as externally registered and remain managed by their files in `~/.omux/plugins/`.

## Registry discovery and install

OpenMUX can discover and install plugin packages from TOML registries. The official default registry is:

```text
https://github.com/finger-gun/omux-plugins
```

Remote registry commands are explicit so the existing picker remains the default for `omux plugins`:

```sh
omux plugins discover
omux plugins discover --json
omux plugins install <plugin-id>
omux plugins update <plugin-id>
omux plugins uninstall <plugin-id>
```

Use `--registry <url>` to discover or install from a custom registry for one command. Registry-installed plugins are copied into `~/.omux/plugins/<command>/` and then discovered by the same local plugin registry as manually installed plugins.

A registry root contains `catalog.toml`:

```toml
schema = 1

[packages.hello-pane]
kind = "plugin"
name = "Hello Pane"
description = "Creates a sample extension pane."
version = "0.1.0"
path = "plugins/hello-pane/omux-plugin.toml"
tags = ["demo"]
```

The package manifest declares the command, entrypoint, and files:

```toml
schema = 1
id = "hello-pane"
name = "Hello Pane"
description = "Creates a sample extension pane."
version = "0.1.0"
license = "Apache-2.0"
kind = "plugin"

[plugin]
command = "hello-pane"
entrypoint = "plugin"

[files.entrypoint]
source = "plugin"
target = "plugin"
executable = true
```

Installing a plugin installs executable local code. OpenMUX prints the source registry, package version, and target paths before install; use `--yes` for non-interactive installs. Installed package receipts live under `~/.omux/installed/` so update and uninstall only remove files OpenMUX installed.

## Plugin process environment

When OpenMUX runs a plugin, it passes the remaining CLI arguments through unchanged and adds these environment variables:

| Variable | Meaning |
| --- | --- |
| `OMUX_PLUGIN_COMMAND` | Command name the user invoked. |
| `OMUX_PLUGIN_EXECUTABLE` | Absolute path to the executable OpenMUX launched. |
| `OMUX_PLUGINS_DIR` | Directory containing the plugin executable. |

Plugins can call back into `omux extension-pane`, `omux pane-status`, `omux notify`, and other public commands to interact with the running app.

## Minimal plugin example

Create `~/.omux/plugins/hello-pane`:

```bash
#!/usr/bin/env bash
set -euo pipefail

omux extension-pane create \
  --plugin dev.example.hello-pane \
  --title "Hello" \
  --html "<main><h1>Hello from a plugin</h1><p>This pane is owned by OpenMUX.</p></main>"
```

Then make it executable and run it:

```sh
chmod +x ~/.omux/plugins/hello-pane
omux hello-pane
```

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

## Terminal text activation

OpenMUX emits an input hook when a user intentionally activates text in a terminal, currently through Command-click. Plugins can listen for this hook and decide whether to act on local paths, URLs, issue IDs, or other recognizable tokens.

| Hook | Payload |
| --- | --- |
| `input:terminal-text-activated` | `token`, `row`, `column`, `cwd`, `resolvedPath`, and numeric `modifiers`. |

Plain clicks remain terminal-owned for focus, selection, and TUI mouse reporting.

The same activation is visible in `omux events` as `terminal.textActivated`. When OpenMUX can handle the Command-hovered token, the terminal view shows a pointer affordance before the click.

## Bundled plugins

Bundled plugins are documented separately:

- [Markdown Preview](./plugins/markdown-preview.md)
