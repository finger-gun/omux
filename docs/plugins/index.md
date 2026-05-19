# OpenMUX Plugin Index

This index lists bundled plugins, highlights useful registry-hosted plugins, and points to the plugin ecosystem docs for creating your own integrations.

## Bundled plugins

| Plugin | Command | What it does |
| --- | --- | --- |
| [Markdown Preview](./markdown-preview.md) | `omux markdown-preview` | Opens GitHub-flavored Markdown previews in extension panes, with watch mode and Command-click activation for local Markdown paths. |
| AI Status | `omux ai-status` | Bundled multi-vendor AI/tool status host. Starts with a Codex adapter and leaves future adapters behind the same command. |

## Managing plugins

Run the interactive plugin picker:

```sh
omux plugins
```

Use the picker to search bundled plugins and toggle configurable ones. External plugins are discovered from `~/.omux/plugins/` and are enabled or disabled by adding or removing executable plugin files.

Discover and install registry-hosted plugins:

```sh
omux plugins discover
omux plugins install <plugin-id>
omux plugins update <plugin-id>
omux plugins uninstall <plugin-id>
```

OpenMUX uses `https://github.com/finger-gun/omux-plugins` by default and accepts `--registry <url>` for custom registries.

## Registry-hosted plugins

| Plugin | Command | What it does |
| --- | --- | --- |
| Settings UI | `omux settings-ui` | Opens a graphical editor for supported `config.toml` settings and saves through OpenMUX validation. |
| Hello Pane | `omux hello-pane` | Opens a small demo extension pane. Useful when testing plugin install and pane creation. |
| macOS Notify | `omux macos-notify` | Sends a macOS notification from a plugin command. |

Install one with:

```sh
omux plugins install ai-status
```

Inspect plugin registration:

```sh
omux plugin list
omux plugin path
```

## Create your own

Read [Plugin Ecosystem](../plugins.md) for command registration, extension panes, process environment, menu contributions, and terminal text activation hooks. For the shared AI status host specifically, see [AI Status](./ai-status.md).
