# OpenMUX Developer Quick Start

This page is the short path for working on OpenMUX locally. For deeper architecture notes, see [Development notes](./development.md).

## First-time setup

OpenMUX depends on a pinned, vendored Ghostty runtime. Build that runtime before normal Swift builds:

```bash
make setup
```

`make setup` runs `Scripts/build-ghostty.sh` and produces the local `GhosttyKit.xcframework` used by app launches and tests.

## Daily development loop

Use the Makefile entrypoints first:

```bash
make app
make test
make verify
```

| Command | Use it for |
| --- | --- |
| `make app` | Launch the local `OpenMUXApp` build for manual testing. |
| `make dev` | Alias for launching the local app with the Ghostty resource path configured. |
| `make build` | Build Swift packages and app targets. |
| `make test` | Run the Swift test suite. |
| `make verify` | Run build and tests. |
| `make smoke` | Launch and sample `OpenMUXApp` as a smoke test. |

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

OpenSpec changes should also be validated with the relevant change ID:

```bash
openspec validate <change-id> --strict
```

## Useful docs while developing

- [Development notes](./development.md) - module boundaries, runtime bridge details, command list, and current implementation status.
- [Plugin ecosystem](./plugins.md) - external plugin commands, extension panes, menu contributions, and terminal text activation hooks.
- [Plugin index](./plugins/index.md) - bundled and registry-hosted plugin docs.
- [Configuration and themes](./configuration.md) - config schema, theme tokens, keybindings, and bundled plugin settings.
- [Hooks](./hooks.md) - hook names, payloads, and automation examples.
- [Releasing](./releasing.md) - packaging and release flow.
- [Manifesto](./manifest.md) - product and architecture guardrails.

## Local cleanup

Inspect cleanup first:

```bash
Scripts/uninstall-local.sh --dry-run
```

Then remove local app bundles, CLI links, `~/.omux`, OpenMUX Application Support state, preferences, caches, saved app state, and update staging leftovers:

```bash
make uninstall-local
```
