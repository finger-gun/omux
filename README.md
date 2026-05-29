<p align="center">
  <img src="./assets/logo.png" alt="OpenMUX logo" width="900" />
</p>

<h1 align="center">OpenMUX</h1>

<p align="center">
  Native macOS terminal workspace for developers.
</p>

<p align="center">
 Fast, flexible, scriptable, and terminal-first.
</p>

<p align="center">
  <span>
    <a href="https://github.com/finger-gun/omux/actions/workflows/ci.yml"><img src="https://github.com/finger-gun/omux/actions/workflows/ci.yml/badge.svg?branch=main" alt="Unit Tests Status" /></a>
    <a href="https://github.com/finger-gun/omux/actions/workflows/ui-tests.yml"><img src="https://github.com/finger-gun/omux/actions/workflows/ui-tests.yml/badge.svg" alt="UI Test Status" /></a>
    <img src="https://img.shields.io/badge/Status-Beta-F59E0B?style=flat-square" alt="Beta status" />
    <img src="https://img.shields.io/badge/Platform-macOS-111827?style=flat-square" alt="macOS platform" />
    <img src="https://img.shields.io/badge/AI-Friendly-7C3AED?style=flat-square" alt="AI-friendly" />
    <img src="https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square" alt="Apache 2.0 license" />
  </span>
</p>

<p align="center">
  <a href="https://openmux.fingergun.dev/">Website</a>
  ·
  <a href="./docs/README.md">Docs</a>
  ·
  <a href="./docs/getting-started.md">Get Started</a>
  ·
  <a href="./docs/configuration.md">Configuration</a>
  ·
  <a href="./docs/plugins/index.md">Plugins</a>
  ·
  <a href="./docs/developer.md">Development</a>
</p>

---

![OpenMUX in action](assets/animated.gif)

## What OpenMUX is

OpenMUX is a native macOS terminal workspace. It gives you workspaces, tabs, split panes, pane-local tab stacks, persistent shell sessions, themes, a local CLI, hooks, bundled plugins, registry-installed plugins, and extension panes.

The goal is simple: keep the terminal powerful, inspectable, and open to your workflow.

## Why OpenMUX?

OpenMUX is built for developers who want a terminal workspace that stays native, scriptable, and inspectable instead of turning into a browser shell or a closed workflow product.

- Terminal first: workspaces, split panes, pane-local tabs, shell history isolation, bounded scrollback restore, and keyboard-first navigation are core product behavior.
- Open by design: the local `omux` CLI, JSON-RPC control plane, hooks, and event stream are public surfaces, not private implementation details.
- AI-friendly, not AI-first: OpenMUX includes local agent tooling and Agent Sessions, but the terminal remains the product and automation remains user-controlled.
- Native and hackable: the app shell is AppKit-first, plugin and hook surfaces are plain local executables, and user-owned configuration stays in `~/.omux/`.


OpenMUX is still in beta, but the main features are already broad and stable.

## Start here

Quick install from the latest GitHub Release:

```bash
curl -fsSL https://github.com/finger-gun/omux/releases/latest/download/openmux-install.sh | bash
```

This installs `OpenMUX.app` and links the bundled `omux` CLI at `~/.local/bin/omux`.

User docs:

- [Getting started](./docs/getting-started.md) - install, first launch, CLI setup, workspaces, panes, themes, hooks, plugins, and the release installer script.
- [Configuration and themes](./docs/configuration.md) - `~/.omux/config.toml`, themes, terminal settings, keybindings, local agent settings, and plugin config.
- [Agent Sessions](./docs/agent-sessions.md) - search, resume, monitor, and delete locally indexed coding-agent sessions from built-in and plugin-provided adapters.
- [Hooks](./docs/hooks.md) - executable user hooks, registry installs, hook payloads, and automation examples.
- [Plugins](./docs/plugins/index.md) - bundled plugins, registry installs, and plugin management.
- [Plugin ecosystem](./docs/plugins.md) - how to create external plugin commands, extension panes, and menu contributions.

Contributor docs:

- [Developer quick start](./docs/developer.md) - local setup, Makefile workflow, and validation commands.
- [Development notes](./docs/development.md) - module boundaries and runtime bridge details.
- [Releasing](./docs/releasing.md) - package and GitHub Release flow.
- [Manifesto](./docs/manifest.md) - product principles and architectural guardrails.

## Common user commands

If you installed the app without the CLI, link the bundled command from the app:

```bash
/Applications/OpenMUX.app/Contents/MacOS/omux install-cli
```

Then use it to control the running app:

```bash
omux help
omux open ~/projects/my-project
omux list --full
omux split right
omux run --focused -- "git status"
omux agent
omux agent -p "Summarize README.md into a short next-action list for a new contributor."
omux theme
omux agent-sessions open
omux plugins
omux events
```

The CLI talks to the running app over a local Unix socket. UI actions and CLI commands target the same live workspaces and shell sessions.

## Configuration

OpenMUX stores user configuration in:

```text
~/.omux/config.toml
```

Create a starter config:

```bash
omux config init
omux config doctor
omux config open
omux config reload
```

User-owned files live under `~/.omux/`:

| Path | Purpose |
| --- | --- |
| `~/.omux/config.toml` | User configuration. |
| `~/.omux/themes/` | Custom themes. |
| `~/.omux/hooks/` | User hook handlers. |
| `~/.omux/plugins/` | External plugin commands. |
| `~/.omux/installed/` | Receipts for registry-installed hooks and plugins. |
| `~/.omux/agent-sessions.sqlite` | Local Agent Sessions index. |
| `~/.omux/generated/ghostty/` | OpenMUX-managed generated terminal config. |

## Plugins

OpenMUX has two plugin and automation surfaces:

1. Bundled plugins, such as Markdown Preview and AI Status, can be toggled with `omux plugins`.
2. User plugins are executable commands discovered from `~/.omux/plugins/`.

Plugins can create extension panes with `omux extension-pane`, listen through hooks, call back into the public CLI, and contribute native menu items. Hooks are executable event handlers under `~/.omux/hooks/`.

`omux agent` is a local assistant for quick automation, repo inspection, and simple OpenMUX control.

- Modes: `omux agent` opens an ephemeral full-screen REPL by default. Use `omux agent -p "..."` for one-shot mode that prints a single plain-text response to stdout; non-interactive use requires `-p`.
- Interactive features: The REPL supports multi-turn chat, streaming output, inline tool activity, status/footer telemetry, and host-handled slash commands such as `/help`, `/tools`, `/stats`, `/compact`, `/handoff`, and `/exit`.
- File, history, and plugin access: Both modes can read recent terminal history from OpenMUX, run non-interactive `omux` subcommands through built-in tools, read or grep files under the current working directory, and load plugin-defined tools from installed manifest plugins.
- Flags and security: Use `--verbose` to print progress such as session startup and tool calls to stderr. Use `--allow-read-anywhere` to let the read-file tool open any readable local path; `grep` remains scoped to the current working directory. Use `--enabled-tools read_file,agenttools.webpage` or `--enabled-tools none` to narrow tools for one invocation. External plugin-defined agent tools default to a 120-second host timeout, configurable with `[agent].external_tool_timeout_seconds`.

Official registries:

| Registry | Repository |
| --- | --- |
| Hooks | <https://github.com/finger-gun/omux-hooks> |
| Plugins | <https://github.com/finger-gun/omux-plugins> |

Discover registry packages with `omux hooks discover` and `omux plugins discover`. See [Hooks](./docs/hooks.md) for the hook system, [Plugin ecosystem](./docs/plugins.md) for the plugin contract, and [Plugin index](./docs/plugins/index.md) for bundled and registry-hosted plugins.

Registry-hosted Agent Sessions plugins can extend support beyond the bundled adapters. Current examples include OpenCode, KiloCode, and OMP.

## Status

OpenMUX is in beta. The foundations are in place, but some areas are still evolving: runtime transcript quality, layout restore polish, pane-stack ergonomics, plugin capabilities, and release packaging.

For current direction, see [Roadmap](./docs/roadmap.md).

## Contributing

Please read [Developer quick start](./docs/developer.md), [Development notes](./docs/development.md), [CONTRIBUTING](./CONTRIBUTING.md), and [CODE OF CONDUCT](./CODE_OF_CONDUCT.md) before opening a pull request.

## License

OpenMUX is released under **Apache-2.0**. See [LICENSE](./LICENSE).

---

<div align="center">

<b>Build your terminal workspace, not someone else's.</b>

<a href="https://openmux.fingergun.dev/">openmux.fingergun.dev</a> · A <a href="https://fingergun.dev/">Finger Gun</a> project.

</div>
