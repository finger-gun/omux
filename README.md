<p align="center">
  <img src="./assets/logo.png" alt="OpenMUX logo" width="900" />
</p>

<h1 align="center">OpenMUX</h1>

<p align="center">
  Native macOS terminal workspace for developers.
</p>

<p align="center">
  Fast, native, flexible, and hackable. Terminal-first, scriptable by default, and built to stay open to your workflow.
</p>

<p align="center">
  <span>
    <a href="https://github.com/finger-gun/omux/actions/workflows/ci.yml"><img src="https://github.com/finger-gun/omux/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status" /></a>
    <img src="https://img.shields.io/badge/Status-Beta-F59E0B?style=flat-square" alt="Beta status" />
    <img src="https://img.shields.io/badge/Platform-macOS-111827?style=flat-square" alt="macOS platform" />
    <img src="https://img.shields.io/badge/AI-Friendly-7C3AED?style=flat-square" alt="AI Friendly" />
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
  <a href="./docs/manifest.md">Manifesto</a>
  ·
  <a href="./docs/configuration.md">Configuration</a>
  ·
  <a href="./docs/hooks.md">Hooks</a>
  ·
  <a href="./docs/development.md">Development</a>
  ·
  <a href="./docs/releasing.md">Releases</a>
</p>

---

![OpenMUX in action](assets/screen-1.png)

## Why OpenMUX

The terminal should be a workspace, not a locked box.

OpenMUX exists for developers who want native terminal workflows without giving up inspectability, scriptability, or control. It takes the opposite bet from bloated, vendor-shaped terminals: keep the core small, keep the seams visible, and let hooks, events, and commands do the heavy lifting.

## What OpenMUX can do today

OpenMUX is already a usable beta foundation with:

- native macOS shell chrome built AppKit-first
- workspaces, top-level tabs, split panes, and pane-local tab stacks
- persistent interactive shell sessions with direct typing, paste, resize, and command injection
- a local `omux` CLI plus JSON-RPC control plane
- external hooks and a mixed local event stream via `omux events`
- token-based theme ownership with built-in themes and user overrides
- required vendored Ghostty runtime hosting behind a narrow OpenMUX bridge
- explicit keyboard-correctness work for ISO layouts, Option behavior, dead keys, compose input, and IME-sensitive flows

## Start using OpenMUX

The user documentation starts at [docs/README.md](./docs/README.md), with a first-run guide in [docs/getting-started.md](./docs/getting-started.md).

Useful user references:

- [Getting started](./docs/getting-started.md) for install, first launch, the `omux` CLI, workspaces, panes, themes, and a first hook.
- [Configuration and themes](./docs/configuration.md) for `~/.omux/config.toml`, theme selection, custom tokens, and terminal settings.
- [Hooks](./docs/hooks.md) for executable user hooks in `~/.omux/hooks/`, invocation JSON, and automation examples.

## Workspace primitives

OpenMUX is built around durable primitives instead of one blessed workflow:

- **Workspaces** for project-level context
- **Tabs** for top-level workspace organization
- **Split panes** for side-by-side and stacked layouts
- **Pane-local tab stacks** for multiple sessions inside one split region
- **Persistent sessions** so UI actions and CLI automation target the same live shell
- **Hooks, events, and commands** as first-class extension seams

## `omux` and the local control plane

The CLI talks to the running app over a local JSON-RPC Unix socket boundary.

Current examples:

```bash
omux list
omux open [path]
omux workspace-close [workspace-id]
omux tab
omux split down
omux pane-remove [--pane <pane-id>]
omux pane-tab
omux pane-tab-next
omux pane-tab-prev
omux pane-tab-focus <pane-id>
omux pane-tab-close [pane-id]
omux run <session-id> "pwd"
omux notify "Build finished"
omux events
```

`omux events` now streams both:

- `terminal.*` runtime events such as cwd changes, title changes, bells, progress, command completion, and renderer health
- successful shared action events such as `workspace.opened`, `tab.created`, `pane.split`, `paneTab.created`, `paneTab.focused`, `paneTab.closed`, `session.focused`, `command.started`, `notification.raised`, and `workspace.restored`

## Architecture direction

OpenMUX keeps a narrow core with stable seams:

- **AppKit-first shell** for windows, focus, menus, notifications, and precision input behavior
- **Thin `libghostty` bridge** so higher-level product logic stays in OpenMUX-native concepts
- **Local-first control plane** through `omux` and JSON-RPC
- **Hooks and events** for lifecycle, session, command, UI, and future plugin automation
- **External plugin processes first** instead of hardwiring one workflow into the app

The product speaks in OpenMUX concepts: workspaces, tabs, panes, sessions, hooks, notifications, commands, and events.

## Configuration and themes

OpenMUX owns its user-facing configuration:

- config file: `~/.omux/config.toml`
- custom themes: `~/.omux/themes/`
- generated Ghostty artifacts: `~/.omux/generated/ghostty/`

`omux config init` writes the complete default config, including the `[keys]` table. Map a binding to `"none"` when an OpenMUX shortcut conflicts with a terminal application shortcut you want to preserve.

Built-in themes currently include:

- `monokai-soda`
- `catppuccin`
- `dracula`
- `nord`
- `gruvbox`
- `one-dark`
- `solarized-dark`
- `solarized-light`

Useful commands:

```bash
omux config init
omux config doctor
omux config reload
omux theme list
omux theme nord
```

## Quick start for contributors

OpenMUX uses Swift Package Manager with a vendored Ghostty runtime path.

```bash
make setup
make dev
make test
make verify
swift run OpenMUXApp
```

If you want the current module boundaries, runtime build notes, and command list, see [docs/development.md](./docs/development.md).

## Releases and installation

OpenMUX has an early GitHub Release flow for downloadable macOS artifacts.

- local packaging: `make package-release` using the root `VERSION`
- release prep: `Scripts/check-changes-since-release.sh` then `Scripts/prepare-release.sh <version>`
- tag-driven GitHub Releases on `v*`
- unsigned macOS app and CLI archives plus checksums

The app bundle includes a bundled `omux` binary. You can install it from the app with **OpenMUX -> Install omux CLI**, or from Terminal with:

```bash
/Applications/OpenMUX.app/Contents/MacOS/omux install-cli
```

For the exact packaging and release flow, see [docs/releasing.md](./docs/releasing.md).

## Status

OpenMUX is in **beta**.

The foundations are now in place:

1. Native app shell, workspace tabs, split panes, and pane-local tabs
2. `omux` CLI, JSON-RPC control plane, hooks, and local events
3. Required vendored Ghostty runtime path
4. Theme/config ownership in OpenMUX-native terms
5. CI and first-pass release automation

Current follow-on areas include transcript quality, layout restore polish, richer automation, and a broader plugin story.

## Project principles

OpenMUX is:

- **Open by design**
- **Terminal first**
- **Native where it matters**
- **Hackable over bloated**
- **AI-friendly, not AI-first**
- **International-first for keyboard correctness**

Read the full rationale in the [manifesto](./docs/manifest.md).

## Contributing

Please read [CONTRIBUTING](./CONTRIBUTING.md) and [CODE OF CONDUCT](./CODE_OF_CONDUCT.md) before opening a pull request.

## License

OpenMUX is released under **Apache-2.0**. See [LICENSE](./LICENSE).

---

<div align="center">

<b>Build your terminal workspace, not someone else's.</b>

<a href="https://openmux.fingergun.dev/">openmux.fingergun.dev</a> · Built with ❤️ in Skåne. A <a href="https://fingergun.dev/">Finger Gun</a> project.

</div>
