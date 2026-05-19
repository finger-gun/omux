# OpenMUX Documentation

OpenMUX documentation starts with people using the app, then branches into automation and contributor references.

If you are new to OpenMUX, start with [Getting started](./getting-started.md). It covers the current beta install path, first launch, the `omux` CLI, themes, hooks, plugins, and where user files live.

## Choose your path

| You want to... | Start here | Then read |
| --- | --- | --- |
| Use OpenMUX as your daily terminal workspace | [Getting started](./getting-started.md) | [Configuration and themes](./configuration.md) |
| Search, resume, and monitor coding-agent sessions | [Agent Sessions](./agent-sessions.md) | [Configuration and themes](./configuration.md#agent-sessions-settings), [AI Status plugin](./plugins/ai-status.md) |
| Customize themes, fonts, scrollback, or Option-key behavior | [Configuration and themes](./configuration.md) | [Getting started](./getting-started.md#customize-the-terminal) |
| Search and run commands from the keyboard | [Command palette](./command-palette.md) | [Configuration and themes](./configuration.md) |
| Automate your workspace with scripts | [Hooks](./hooks.md) | [Configuration and themes](./configuration.md#cli) |
| Install hooks or plugins from registries | [Hooks](./hooks.md#registry-discovery-and-install), [Plugin index](./plugins/index.md#managing-plugins) | [Configuration and themes](./configuration.md#registries-settings) |
| Use bundled or registry-hosted plugins | [Plugin index](./plugins/index.md) | [Configuration and themes](./configuration.md#plugins-settings) |
| Create a plugin, extension pane, or menu contribution | [Plugin ecosystem](./plugins.md) | [Hooks](./hooks.md) |
| Understand where the product is headed | [Roadmap](./roadmap.md) | [Manifesto](./manifest.md) |
| Contribute to OpenMUX itself | [Developer quick start](./developer.md) | [Architecture overview](./architecture.md), [Development notes](./development.md), [Releasing](./releasing.md), [CONTRIBUTING](../CONTRIBUTING.md) |
| Research architecture and terminal-engine boundaries | [Research notes](./research/) | [Manifesto](./manifest.md), [Development notes](./development.md) |

## For users

These docs describe OpenMUX from the outside: what you can run, configure, and automate.

- [Getting started](./getting-started.md) - first launch, CLI setup, workspaces, panes, themes, plugins, and simple automation.
- [Configuration and themes](./configuration.md) - `~/.omux/config.toml`, built-in themes, custom theme tokens, Settings UI, and config commands.
- [Agent Sessions](./agent-sessions.md) - search, resume, monitor, and delete locally indexed coding-agent sessions.
- [Command palette](./command-palette.md) - opening modes, keyboard navigation, and how to add new commands.
- [Plugin index](./plugins/index.md) - bundled plugins, registry-hosted plugins, and plugin management.
- [Plugin ecosystem](./plugins.md) - external plugin commands, extension-pane CLI contracts, menu contributions, and plugin events.
- [Hooks](./hooks.md) - executable user hooks in `~/.omux/hooks/`, registry installs, invocation JSON, current hook names, and examples.
- [Roadmap](./roadmap.md) - what works today and what is next.

## For contributors

These docs are for changing OpenMUX itself.

- [Developer quick start](./developer.md) - first-time setup, daily commands, validation, and links for contributors.
- [Architecture overview](./architecture.md) - system boundaries, render tree, workspace model, and modal/pane relationships.
- [Development notes](./development.md) - module boundaries, build commands, runtime bridge notes, and current limitations.
- [Releasing](./releasing.md) - local packaging, GitHub Release flow, and current distribution status.
- [Manifesto](./manifest.md) - product principles and architectural guardrails.
- [Research notes](./research/) - background investigations for configuration, action dispatch, and foundation decisions.

## User file locations

OpenMUX keeps user-owned files under `~/.omux/`:

| Path | Purpose |
| --- | --- |
| `~/.omux/config.toml` | User configuration for themes, terminal settings, keybindings, and bundled plugins. |
| `~/.omux/themes/` | User theme overrides and custom themes. |
| `~/.omux/hooks/` | Executable hook handlers grouped by hook name. |
| `~/.omux/plugins/` | Executable plugin commands discoverable as `omux <plugin-command>`. |
| `~/.omux/installed/` | Receipts for packages installed from hook and plugin registries. |
| `~/.omux/generated/ghostty/` | Generated terminal-engine artifacts managed by OpenMUX. |

The generated directory is not the primary user API. Prefer editing `config.toml`, theme files, hook files, and plugin executables.
