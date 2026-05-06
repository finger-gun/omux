# OpenMUX Documentation

OpenMUX documentation starts with people using the app, then branches into automation and contributor references.

If you are new to OpenMUX, start with [Getting started](./getting-started.md). It covers the current beta install path, first launch, the `omux` CLI, themes, and where user files live.

## Choose your path

| You want to... | Start here | Then read |
| --- | --- | --- |
| Use OpenMUX as your daily terminal workspace | [Getting started](./getting-started.md) | [Configuration and themes](./configuration.md) |
| Customize themes, fonts, scrollback, or Option-key behavior | [Configuration and themes](./configuration.md) | [Getting started](./getting-started.md#customize-the-terminal) |
| Automate your workspace with scripts | [Hooks](./hooks.md) | [Configuration and themes](./configuration.md#cli) |
| Build or use optional content-pane plugins | [Plugins and extension panes](./plugins.md) | [Configuration and themes](./configuration.md#pluginsmarkdown-preview-settings) |
| Understand where the product is headed | [Roadmap](./roadmap.md) | [Manifesto](./manifest.md) |
| Contribute to OpenMUX itself | [Development notes](./development.md) | [Releasing](./releasing.md), [CONTRIBUTING](../CONTRIBUTING.md) |
| Research architecture and terminal-engine boundaries | [Research notes](./research/) | [Manifesto](./manifest.md), [Development notes](./development.md) |

## For users

These docs describe OpenMUX from the outside: what you can run, configure, and automate.

- [Getting started](./getting-started.md) - first launch, CLI setup, workspaces, panes, themes, and simple automation.
- [Configuration and themes](./configuration.md) - `~/.omux/config.toml`, built-in themes, custom theme tokens, and config commands.
- [Plugins and extension panes](./plugins.md) - optional plugin workflows, extension-pane CLI contracts, and Markdown preview.
- [Hooks](./hooks.md) - executable user hooks in `~/.omux/hooks/`, invocation JSON, current hook names, and examples.
- [Roadmap](./roadmap.md) - what works today and what is next.

## For contributors

These docs are for changing OpenMUX itself.

- [Development notes](./development.md) - module boundaries, build commands, runtime bridge notes, and current limitations.
- [Releasing](./releasing.md) - local packaging, GitHub Release flow, and current distribution status.
- [Manifesto](./manifest.md) - product principles and architectural guardrails.
- [Research notes](./research/) - background investigations for configuration, action dispatch, and foundation decisions.

## User file locations

OpenMUX keeps user-owned files under `~/.omux/`:

| Path | Purpose |
| --- | --- |
| `~/.omux/config.toml` | User configuration for theme and terminal settings. |
| `~/.omux/themes/` | User theme overrides and custom themes. |
| `~/.omux/hooks/` | Executable hook handlers grouped by hook name. |
| `~/.omux/generated/ghostty/` | Generated terminal-engine artifacts managed by OpenMUX. |

The generated directory is not the primary user API. Prefer editing `config.toml`, theme files, and hook files.
