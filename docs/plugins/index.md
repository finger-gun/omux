# OpenMUX Plugin Index

This index lists bundled plugins and points to the plugin ecosystem docs for creating your own integrations.

## Bundled plugins

| Plugin | Command | Default | What it does |
| --- | --- | --- | --- |
| [Markdown Preview](./markdown-preview.md) | `omux markdown-preview` | Enabled | Opens GitHub-flavored Markdown previews in extension panes, with watch mode and Command-click activation for local Markdown paths. |

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

Inspect plugin registration:

```sh
omux plugin list
omux plugin path
```

## Create your own

Read [Plugin Ecosystem](../plugins.md) for command registration, extension panes, process environment, and terminal text activation hooks.
