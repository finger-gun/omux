## Why

OpenMUX already supports local executable hooks and CLI plugins, but users must manually discover, copy, and manage them. A repository-backed discovery and install flow makes the hook/plugin ecosystem usable without making the core monolithic or opinionated.

## Goals

- Make hooks and plugins discoverable from official OpenMUX registries and user-provided registries.
- Install packages into the existing `~/.omux/hooks` and `~/.omux/plugins` layouts so runtime discovery remains simple and local-first.
- Use explicit TOML metadata and install receipts so packages are inspectable, updateable, and removable.
- Keep the experience terminal-first through `omux` CLI commands rather than an app marketplace UI.

## Non-goals

- No in-app browser marketplace or long-running background registry service.
- No in-process plugin runtime, sandbox, or WASM execution in this change.
- No automatic execution of downloaded code during install.
- No changes to libghostty or the terminal bridge boundary.

## What Changes

- Add remote extension package/catalog metadata for hook and plugin registries.
- Add default official registries for `finger-gun/omux-hooks` and `finger-gun/omux-plugins`.
- Add support for custom registry URLs from CLI flags and configuration.
- Add `omux hooks discover/install/uninstall/update` commands.
- Extend `omux plugins` with `discover/install/uninstall/update` while preserving the current picker when no subcommand is provided.
- Install hooks/plugins through a validated staging flow with path traversal protection, executable permissions, and install receipts.
- Document registry authoring, package metadata, install commands, and executable-code trust expectations.

## Capabilities

### New Capabilities

- `extension-registries`: Repository-backed hook/plugin catalog discovery, installation, update, uninstall, and custom registry configuration.

### Modified Capabilities

- `hooks-foundation`: Hooks installed from registries must use the existing local hook directory contract.
- `markdown-preview-plugin`: Plugin registry commands must preserve existing bundled/external plugin listing and picker behavior.
- `config-system`: Configuration must support custom hook/plugin registry URL lists.

## Impact

- Affected code: `Sources/OmuxCLI`, `Sources/OmuxConfig`, `Sources/OmuxHooks`, plugin registry code, docs, and tests.
- APIs/contracts: new CLI commands and TOML metadata contracts for registries/packages/install receipts.
- Dependencies: no new parser dependency; TOML metadata should reuse existing config parsing utilities.
- Extension points: strengthens hooks/plugins as external, executable, local-first contracts.
- Input/keyboard: no direct keyboard handling changes.
- libghostty bridge: no impact; the feature stays above the terminal engine boundary.
