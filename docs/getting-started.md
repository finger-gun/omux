# Getting Started with OpenMUX

OpenMUX is a beta macOS terminal workspace. It gives you native windows, workspaces, tabs, split panes, persistent shell sessions, themes, a local `omux` CLI, user hooks, and plugins.

This guide is for people who want to use OpenMUX, not contribute to its internals.

## 1. Install the app

OpenMUX currently publishes early macOS artifacts through [GitHub Releases](https://github.com/finger-gun/omux/releases).

1. Download the latest `OpenMUX-<version>-macos-unsigned.zip` from the project releases.
2. Unzip it and move `OpenMUX.app` to `/Applications`.
3. Open the app from Finder.

The current app archive is ad-hoc signed so the bundle is structurally valid, but it is not yet Developer ID signed or notarized. macOS may require you to approve the app from **System Settings -> Privacy & Security** the first time you open it. The release flow is expected to move to fully signed and notarized artifacts later.

If you are testing from source instead of a release artifact, see the [Developer quick start](./developer.md).

## 2. Install the `omux` CLI

The app bundle includes the `omux` command-line tool. Install it from the app with:

```text
OpenMUX -> Install omux CLI
```

You can also install it from Terminal:

```bash
/Applications/OpenMUX.app/Contents/MacOS/omux install-cli
```

After installation, check that the command is available:

```bash
omux help
omux version
```

If the installer falls back to `~/.local/bin/omux`, make sure `~/.local/bin` is on your shell `PATH`.

## 2.1. Update OpenMUX

Once `omux` is installed, you can check and install newer GitHub Release app archives from Terminal:

```bash
omux update
```

The updater downloads the latest app archive and `checksums.txt`, verifies the SHA-256 checksum, unarchives into a per-user temporary staging directory, validates the app bundle, and then installs `OpenMUX.app`. If OpenMUX is running, it prompts before closing it:

```text
Close OpenMUX to install 0.5.0 to /Applications/OpenMUX.app? [Y/n]
```

Press Return or answer `y` to continue; answer `n` to cancel without changing the installed app. The final replacement runs from a detached helper copied into the temporary staging directory, so the update can continue even when the command was launched from an OpenMUX terminal pane.

The updater targets the current installed app when it can determine that location. Otherwise it uses `/Applications/OpenMUX.app` when writable, or `~/Applications/OpenMUX.app` for user-local installs. It does not invoke hidden `sudo` or request administrator privileges.

## 3. Open a workspace

OpenMUX organizes your terminal around workspaces, tabs, split panes, pane-local tabs, and persistent shell sessions.

From the app, open a project folder as a workspace. From Terminal, you can ask the running app to open one:

```bash
omux open ~/projects/my-project
```

Useful workspace commands:

```bash
omux list
omux list --full
omux sessions
omux panes
```

Use `list --full`, `sessions`, and `panes` when you need IDs for automation.

## 4. Work with panes and commands

OpenMUX panes hold live shell sessions. UI actions and CLI commands target those same sessions instead of starting disconnected one-off commands.

Common commands:

```bash
omux tab
omux split right
omux split down
omux pane-remove --focused
omux pane-tab
omux pane-tab-next
omux pane-tab-prev
omux pane-tab-close
omux run --focused -- pwd
omux send-text --focused -- "echo ready"
```

Use `run` when you want OpenMUX to submit a command. Use `send-text` when you only want to insert text without pressing Return.

Terminal-targeting commands accept one explicit selector:

```bash
omux run --session <session-id> -- pwd
omux run --pane <pane-id> -- "pnpm dev"
omux send-text --workspace <workspace-id> -- "notes only"
omux run --focused -- "git status"
```

## 5. Customize the terminal

Create a starter config:

```bash
omux config init
```

Your user config lives at:

```text
~/.omux/config.toml
```

Starter config:

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
"cmd+shift+w" = "pane.remove"
"cmd+t" = "pane-tab.create"
"cmd+w" = "pane-tab.close"
"ctrl+tab" = "pane-tab.next"
```

`omux config init` writes the complete default config, including every default keybinding. Set a binding to `"none"` if OpenMUX conflicts with a terminal app shortcut you want to keep terminal-owned.

List and switch themes:

```bash
omux theme list
omux theme nord
```

Check or reload config after editing:

```bash
omux config doctor
omux config reload
omux plugins
```

For all supported keybindings, default workspace root behavior, theme tokens, built-in themes, plugin settings, and Ghostty pass-through rules, see [Configuration and themes](./configuration.md).

## 6. Add a simple hook

Hooks are executable files that react to OpenMUX events. They live under `~/.omux/hooks/<hook-name>/`.

Create a command-failure notification hook:

```bash
mkdir -p ~/.omux/hooks/command-failed
$EDITOR ~/.omux/hooks/command-failed/20-notify
```

Example handler:

```bash
#!/usr/bin/env bash
set -euo pipefail

cat >/dev/null

osascript -e 'display notification "A command failed in OpenMUX" with title "OpenMUX"'
```

Make it executable:

```bash
chmod +x ~/.omux/hooks/command-failed/20-notify
```

OpenMUX passes hook data as JSON on stdin. Hooks can call `omux` again to split panes, run commands, send text, or inspect workspace state. For the full hook list and payload contract, see [Hooks](./hooks.md).

## 7. Use plugins

List and manage plugins:

```bash
omux plugin list
omux plugins
```

Bundled plugins can be toggled from the interactive picker. External plugins are executable files under `~/.omux/plugins/`; see [Plugin ecosystem](./plugins.md) to create one and [Plugin index](./plugins/index.md) for bundled plugin docs.

## 8. Know where files live

| Path | Purpose |
| --- | --- |
| `~/.omux/config.toml` | User configuration. |
| `~/.omux/themes/` | Custom themes. |
| `~/.omux/hooks/` | User hook handlers. |
| `~/.omux/plugins/` | User plugin commands. |
| `~/.omux/generated/ghostty/` | Generated OpenMUX-managed terminal config. |

Prefer editing `config.toml`, custom theme files, hook files, and plugin executables. The generated Ghostty directory is managed by OpenMUX.

## Next steps

- Read [Configuration and themes](./configuration.md) to customize appearance and terminal behavior.
- Read [Hooks](./hooks.md) to automate workspace actions.
- Read [Plugins](./plugins/index.md) to see bundled plugins and plugin management.
- Read the [Roadmap](./roadmap.md) to understand current beta limitations and planned work.
