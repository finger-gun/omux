# OpenMUX Developer Quick Start

This page is the short path for working on OpenMUX locally. For deeper architecture notes, see [Architecture overview](./architecture.md) and [Development notes](./development.md).

## First-time setup

OpenMUX depends on a pinned, vendored Ghostty runtime. Build that runtime before normal Swift builds:

```bash
make setup
```

`make setup` runs `Scripts/build-ghostty.sh` and produces the local `GhosttyKit.xcframework` used by app launches and tests.

The UI test workflow also needs XcodeGen to regenerate `OpenMUX.xcodeproj` from `project.yml`:

```bash
brew install xcodegen
```

## Daily development loop

Use the Makefile entrypoints first:

```bash
make app
make test
make verify
make power-profile
make ui-test
```

| Command | Use it for |
| --- | --- |
| `make app` | Launch the local `OpenMUXApp` build for manual testing. |
| `make app sandbox=1` | Launch against a fresh, isolated sandbox — no real user data touched. |
| `make dev` | Alias for launching the local app with the Ghostty resource path configured. |
| `make build` | Build Swift packages and app targets. |
| `make test` | Run the Swift test suite. |
| `make verify` | Run build and tests. |
| `make smoke` | Launch and sample `OpenMUXApp` as a smoke test. |
| `make power-profile` | Wait for `OpenMUXApp`, log runtime snapshots while you work, and emit a shareable report on Ctrl-C. |
| `make ui-test` | Run the XCUIAutomation GUI test suite. |

When changing the CLI, use SwiftPM directly:

```bash
swift run omux help
swift run omux config doctor
swift run omux config open
swift run omux theme
swift run omux plugins
swift run omux plugins discover
```

If you install a development CLI into your shell, remember that it talks to the running app over the local control plane. Most commands need `OpenMUXApp` running.

## Common validation

Run the smallest useful check while iterating, then `make verify` before handing off:

```bash
swift test --filter OmuxCLITests
swift test --filter OmuxAppShellTests
swift test --filter OmuxTerminalBridgeTests
make verify
```

When changing AppKit shell behavior, accessibility identifiers, menus, pane chrome, command palette behavior, drag/drop, or UI-test helpers, run the relevant UI test slice:

```bash
make ui-test UI_TEST=PaneTests
make ui-test UI_TEST=CommandPaletteTests/testCommandPaletteOpenClose
```

OpenSpec changes should also be validated with the relevant change ID:

```bash
openspec validate <change-id> --strict
```

## Useful docs while developing

- [Development notes](./development.md) - module boundaries, runtime bridge details, command list, and current implementation status.
- [Architecture overview](./architecture.md) - how OpenMUX speaks over the control plane, renders the shell, and models workspaces, panes, tabs, and modals.
- [Plugin ecosystem](./plugins.md) - external plugin commands, extension panes, menu contributions, and terminal text activation hooks.
- [Plugin index](./plugins/index.md) - bundled and registry-hosted plugin docs.
- [Configuration and themes](./configuration.md) - config schema, theme tokens, keybindings, and bundled plugin settings.
- [Hooks](./hooks.md) - hook names, payloads, and automation examples.
- [Releasing](./releasing.md) - packaging and release flow.
- [Manifesto](./manifest.md) - product and architecture guardrails.

## Sandbox mode

`make app sandbox=1` launches OpenMUX against a fully isolated, throwaway environment instead of your real `~/.omux/` and `~/Library/Application Support/OpenMUX/` data.

**When to use it:**

- Reproducing workspace restore bugs without touching your real session state.
- Testing layout persistence, tab/pane structure, and scrollback before a release.
- Iterating on `current.json` schema changes safely — a malformed fixture never silently falls back to real backups.
- Handing a colleague a fully deterministic starting point ("clone and run `make app sandbox=1`").
- Any situation where you want a clean slate but don't want to wipe your real data.

**What it does:**

1. Wipes `/tmp/omux-sandbox/` and rebuilds it from scratch every time.
2. Creates three stub git repos at `/tmp/omux-sandbox/worktrees/{alpha,beta,gamma}/`.
3. Writes a `config.toml` with test-friendly defaults.
4. Writes a `current.json` fixture: 2 workspaces × 2 tabs × 2-pane horizontal splits, each pane pointing at a worktree directory.
5. Launches `OpenMUXApp` with `OMUX_HOME=/tmp/omux-sandbox` and `OMUX_APP_SUPPORT_DIR=/tmp/omux-sandbox/AppSupport`, so config, socket, hooks, workspace state, scrollback, and backups all land in `/tmp/`.

Your real `~/.omux/` and `~/Library/Application Support/OpenMUX/` are never read or written.

```bash
make app sandbox=1
# or
make dev sandbox=1
```

The sandbox is always reset on each invocation. There is no persistent sandbox state between runs.

## Local cleanup

Inspect cleanup first:

```bash
Scripts/uninstall-local.sh --dry-run
```

Then remove local app bundles, CLI links, `~/.omux`, OpenMUX Application Support state, preferences, caches, saved app state, and update staging leftovers:

```bash
make uninstall-local
```
