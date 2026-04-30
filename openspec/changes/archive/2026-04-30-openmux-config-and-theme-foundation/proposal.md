## Why

OpenMUX runs `libghostty` on whatever defaults it ships with. In `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift` we call `ghostty_config_new()` immediately followed by `ghostty_config_finalize()` with nothing in between — no config is loaded, no theme reaches Ghostty, and there is no path for users to influence terminal behavior. At the same time, `Sources/OmuxAppShell/WorkspaceTheme.swift` carries four hand-coded `WorkspaceShellTheme` Swift constants that style the shell chrome but never reach the engine. Theme and engine are disconnected.

To become a terminal workspace platform rather than a thin Ghostty host, OpenMUX needs to own its own configuration and theming surface, compile that surface into Ghostty config internally, and apply it to the engine — without depending on the user's Ghostty config and without spreading Ghostty config concepts across the codebase. This change is the foundation that later work (per-pane overrides, light/dark resolution, keybindings, action dispatch) builds on.

## What Changes

- **Introduce an OpenMUX-owned config file** at `~/.omux/config.toml` in TOML format, schema-versioned, with documented defaults and validation diagnostics. OpenMUX MUST NOT call `ghostty_config_load_default_files`; the user's Ghostty config is never read.
- **Introduce a token-based theme model.** A theme is a flat TOML file declaring a fixed, documented set of design tokens (chrome surfaces, text, borders, accent, cursor, selection, full ANSI 16-color palette). Both the AppKit shell renderer and the Ghostty config compiler consume the same tokens. No inheritance, no derivation rules at runtime — every theme is fully populated when committed.
- **Ship eight built-in themes as data files**: `monokai-soda` (default), `catppuccin`, `dracula`, `nord`, `gruvbox`, `one-dark`, `solarized-dark`, and `solarized-light`.
- **Add a theme compiler** that translates resolved tokens into Ghostty config text and writes a deterministic generated artifact at `~/.omux/generated/ghostty/config-<hash>` where the hash is a function of token values, config inputs, schema version, and OpenMUX version.
- **Wire the terminal bridge** to load the generated config file via `ghostty_config_load_file` before finalization, and to surface validation diagnostics from `ghostty_config_diagnostics_count` / `ghostty_config_get_diagnostic` upward as OpenMUX-native diagnostics.
- **Support live reload.** When the config file or active theme file changes on disk (or on explicit `omux config reload`), OpenMUX recompiles, writes a new generated file, and applies it via `ghostty_app_update_config` without restarting terminal sessions.
- **Add a `[ghostty]` pass-through section.** Any key under `[ghostty]` in `~/.omux/config.toml` is forwarded into the generated Ghostty config. OpenMUX-managed keys (those derived from theme tokens, font settings, etc.) are emitted last so they always win on collision; collisions emit a diagnostic via `omux config doctor`. No key blocklist is introduced — `action_cb` rejection in the bridge already neutralizes app-shell config.
- **Add a dev-time iTerm2 importer** under `Scripts/` that converts `.itermcolors` files into fully-populated OpenMUX theme TOML files at build time. The importer is not exposed at runtime in this change; the eight built-ins are produced or assisted by it and committed as static files.
- **Replace the hardcoded `WorkspaceShellTheme` Swift constants** with a renderer that reads resolved tokens from the theme system. The four current constants (`openMUXDark`, `catppuccin`, `gruvbox`, `sonokai`) are removed; the new built-in set above takes their place.

## Capabilities

### New Capabilities

- `config-system`: Owns the discovery, parsing, schema validation, layered resolution (built-in defaults → user file), versioning, and live-reload signaling of `~/.omux/config.toml`. Surfaces structured diagnostics for invalid input. Defines the `[ghostty]` pass-through contract and the OpenMUX-managed key list.
- `theme-system`: Owns the token vocabulary, the flat TOML theme file format, theme discovery (built-in plus user themes under `~/.omux/themes/`), token resolution into concrete colors, the compiler from tokens to Ghostty config text, and the deterministic on-disk generated artifact under `~/.omux/generated/ghostty/`. Provides resolved tokens to the AppKit shell renderer.

### Modified Capabilities

- `terminal-bridge`: Adds requirements that the bridge load OpenMUX-generated Ghostty config from a path supplied by the host, MUST NOT call `ghostty_config_load_default_files`, MUST surface Ghostty diagnostics as OpenMUX-native diagnostics, and MUST support live config refresh via `ghostty_app_update_config` without recreating sessions.

## Impact

- **Code**:
  - `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift`: replace blank-config initialization with load-from-path; surface diagnostics; add a refresh entry point.
  - `Sources/OmuxAppShell/WorkspaceTheme.swift`: remove hardcoded preset constants; convert to a token consumer that derives `WorkspaceShellColors` from resolved tokens.
  - New modules: `OmuxConfig` (or equivalent) for config parsing and resolution, `OmuxTheme` for token model and compiler, plus theme-data resource bundles for the eight built-in themes.
  - `Sources/OmuxCLI` / `Sources/omux`: add `omux config doctor` and `omux config reload` subcommands.
  - `Sources/OmuxAppShell` and `Sources/OmuxControlPlane`: subscribe to live reload events and propagate to the bridge and shell renderer.

- **Tooling**:
  - New `Scripts/import-iterm2.swift` (or equivalent) used at development time to produce fully-populated theme TOML files from iTerm2 color schemes.
  - Theme data files committed under the package as resources.

- **Dependencies**:
  - A TOML parser is required. Choice (vendored dep vs. small in-tree subset parser) is deferred to `design.md`.

- **Filesystem**:
  - New user-facing path: `~/.omux/config.toml`.
  - New user-facing directory: `~/.omux/themes/`.
  - New OpenMUX-managed directory: `~/.omux/generated/ghostty/` (created and maintained by OpenMUX; users SHOULD NOT hand-edit).

- **Documentation**:
  - Update `docs/manifest.md`, `docs/development.md`, and `docs/roadmap.md` to reflect the new config and theme story.
  - Add a user-facing reference for the token vocabulary and the `[ghostty]` pass-through contract.

- **Out of scope (deferred to later changes)**:
  - Light/dark auto-resolution driven by macOS appearance.
  - Per-pane theme overrides via `ghostty_surface_update_config`.
  - Keybindings (own change, integrates with the existing `input-pipeline` capability).
  - Runtime `omux import ghostty` / `omux export ghostty` commands.
  - Ghostty action dispatch (`PWD`, `COMMAND_FINISHED`, etc.) — captured in `docs/research/ghostty-action-dispatch.md`.

- **Alignment with manifesto**:
  - *Terminal first*: themes and config exist to make the embedded engine reflect OpenMUX's product identity, not to wrap it in non-terminal chrome.
  - *Open by design*: the entire pipeline is inspectable — the user can read their TOML, the generated Ghostty file under `~/.omux/generated/`, and the diagnostics from `omux config doctor`.
  - *Hackable*: the `[ghostty]` pass-through is a permanent escape hatch so power users are never blocked on OpenMUX adding first-class settings.
  - *International-first*: input-related settings are explicitly deferred to a dedicated keybindings/input change so EU layout and Option/AltGr semantics get the focused treatment they require, not a throwaway field in this proposal.
  - *Bridge boundary*: `libghostty` config types and calls remain confined to `OmuxTerminalBridge`; the rest of the codebase deals in OpenMUX tokens and OpenMUX config values.
