## 1. OmuxConfig module foundation

- [x] 1.1 Add a new `OmuxConfig` Swift package target under `Sources/OmuxConfig/`
- [x] 1.2 Add a TOML parser dependency to `Package.swift` (per design D2; confirm package selection during implementation; fall back to in-tree subset parser if no candidate meets the bar)
- [x] 1.3 Define `OmuxConfigSchemaVersion` constant (= 1) and the `OmuxConfig` value type covering `[theme]`, `[terminal]`, and `[ghostty]` sections
- [x] 1.4 Define `OmuxConfigDiagnostic` (severity, message, file, line) as the OpenMUX-native diagnostic struct shared with the bridge
- [x] 1.5 Implement schema-version handling: reject missing `schema`, reject unknown future versions, hook for future migrations
- [x] 1.6 Implement layered defaults: documented built-in defaults overlaid by user file values
- [x] 1.7 Implement `[ghostty]` pass-through extraction as an ordered key/value list (not interpreted)
- [x] 1.8 Implement file location resolution at `~/.omux/config.toml` with absent-file handling that runs on defaults

## 2. OmuxTheme module foundation

- [x] 2.1 Add a new `OmuxTheme` Swift package target under `Sources/OmuxTheme/`
- [x] 2.2 Define the closed token vocabulary (30 tokens per design D4) as a strongly-typed enum or struct keyed set
- [x] 2.3 Define `Theme` value type: `name`, `displayName`, `tokens: [Token: Color]`, `schema`
- [x] 2.4 Implement theme TOML parser that fails fast on unknown tokens, missing tokens, or `extends`-like keys
- [x] 2.5 Implement theme registry that loads built-ins from `Bundle.module` and user themes from `~/.omux/themes/*.toml`, with user-wins-on-conflict + warning diagnostic
- [x] 2.6 Define `ResolvedThemeTokens` value type exported for the AppKit shell consumer

## 3. Built-in themes (data files)

- [x] 3.1 Create `Sources/OmuxTheme/Resources/themes/` and declare it as a package resource in `Package.swift`
- [x] 3.2 Build/curate `monokai-soda.toml` (default; full 30-token population)
- [x] 3.3 Build/curate `catppuccin.toml`
- [x] 3.4 Build/curate `dracula.toml`
- [x] 3.5 Build/curate `nord.toml`
- [x] 3.6 Build/curate `gruvbox.toml`
- [x] 3.7 Build/curate `one-dark.toml`
- [x] 3.8 Build/curate `solarized-dark.toml`
- [x] 3.9 Build/curate `solarized-light.toml`

## 4. iTerm2 importer (dev-time tool)

- [x] 4.1 Add a Swift script or executable target at `Scripts/import-iterm2/` (per design D12)
- [x] 4.2 Parse `.itermcolors` plist → ANSI 16 + bg/fg/cursor/selection
- [x] 4.3 Implement chrome-derivation heuristics for missing tokens (per design D12; output is a static file, derivation does NOT run at runtime)
- [x] 4.4 Emit a fully-populated OpenMUX theme TOML to a destination path
- [x] 4.5 Document usage in `Scripts/import-iterm2/README.md` so future themes can be added

## 5. Theme-to-Ghostty compiler

- [x] 5.1 Implement token → Ghostty key mapping per design D4 (`bg.canvas` → `background`, ANSI palette → `palette = N=...`, etc.)
- [x] 5.2 Implement OpenMUX-managed key list (per design D7) as the canonical override-source-of-truth
- [x] 5.3 Implement compiled file emitter that writes pass-through keys first, OpenMUX-managed keys last (per spec: last-write-wins is the override mechanism)
- [x] 5.4 Implement collision detection between `[ghostty]` pass-through and the OpenMUX-managed key list, producing warning diagnostics
- [x] 5.5 Implement deterministic hash (sha256, 16 hex chars per design D6) over schema version, OpenMUX build, resolved tokens, sorted pass-through, sorted OMUX-managed keys
- [x] 5.6 Implement header-comment generation (declaring OpenMUX ownership, source path, theme name, version, hash, no-edit notice)
- [x] 5.7 Write generated file to `~/.omux/generated/ghostty/config-<hash>` atomically (write to temp, rename)

## 6. Generated-artifact lifecycle

- [x] 6.1 Implement directory creation under `~/.omux/generated/ghostty/`
- [x] 6.2 Implement garbage collection at launch (per spec; remove non-active files older than retention threshold or from a different OpenMUX build; cap directory size)
- [x] 6.3 Ensure GC never deletes the file the running engine is currently using

## 7. Bridge boundary changes

- [x] 7.1 Add `applyCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic]` to `GhosttyTerminalBridge` / `CGhosttyRuntime`
- [x] 7.2 Replace blank-config initialization in `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift:79-80` with `ghostty_config_new` → `ghostty_config_load_file(path)` → `ghostty_config_finalize` flow
- [x] 7.3 Translate `ghostty_config_diagnostics_count` / `ghostty_config_get_diagnostic` results into `OmuxConfigDiagnostic` values; return them upward
- [x] 7.4 Add `refreshCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic]` that builds a new config object, finalizes, calls `ghostty_app_update_config`, and frees the previous config without recreating sessions
- [x] 7.5 Add a unit test that grep-asserts the bridge module never references `ghostty_config_load_default_files`
- [x] 7.6 Add a smoke test verifying that `applyCompiledConfig` with a known theme produces visible engine state matching the theme tokens (background, palette)

## 8. AppKit shell renderer refactor

- [x] 8.1 In `Sources/OmuxAppShell/WorkspaceTheme.swift`, remove the four hardcoded `WorkspaceShellTheme` constants (`openMUXDark`, `catppuccin`, `gruvbox`, `sonokai`)
- [x] 8.2 Convert `WorkspaceShellColors` into a value type computed from `ResolvedThemeTokens` (per design D10 mapping table)
- [x] 8.3 Move chrome button hover/active tinting from token-derived to renderer-side blending of `bg.elevated` toward `accent`
- [x] 8.4 Update every existing shell-theme call site (`WorkspaceWindowController`, `HostedTerminalPaneView` styling, etc.) to consume `ResolvedThemeTokens` from `OmuxTheme`
- [x] 8.5 Subscribe the shell to theme-change events from `OmuxTheme` and re-render chrome on update

## 9. Explicit reload pipeline

Per scope reduction during implementation, v1 ships **explicit reload** through `omux config reload` instead of a background file-watcher.

## 10. CLI surface

- [x] 10.1 Add `omux config doctor` to `Sources/omux` / `Sources/OmuxCLI`: print all current diagnostics, exit zero on warnings-only, exit non-zero on hard errors
- [x] 10.2 Add `omux config reload`: trigger the same recompile-and-apply pipeline as the explicit app-owned reload path
- [x] 10.3 Add `omux config init`: scaffold a documented starter `~/.omux/config.toml` (refuse to overwrite if file exists; subcommand naming finalized during implementation per design open question)
- [x] 10.4 Wire CLI commands through the existing `omux-control-plane` JSON-RPC where applicable so the running app handles reload, not the CLI binary alone

## 11. Documentation

- [x] 11.1 Add a user-facing reference for the token vocabulary (table mapping tokens to AppKit role and Ghostty key)
- [x] 11.2 Add a user-facing reference for the `[ghostty]` pass-through contract (no allowlist, OMUX-managed keys win, pass-through is not OpenMUX-versioned)
- [x] 11.3 Update `docs/manifest.md` and `docs/development.md` with the new config and theme story
- [x] 11.4 Update `docs/roadmap.md`: move "Theme system and built-in presets" status to reflect the token-based model; mark "Theme customization" item as covered by this change for the user-overrides part

## 12. Tests

- [x] 12.1 Unit tests for `OmuxConfig` parsing (schema mismatch, unknown keys, partial files, `[ghostty]` extraction)
- [x] 12.2 Unit tests for `OmuxTheme` parsing (missing token, unknown token, `extends` rejection, user-wins-on-conflict)
- [x] 12.3 Unit tests for compiler determinism (same inputs → same hash → same output bytes)
- [x] 12.4 Unit tests for compiler emit order (pass-through before OMUX-managed; collision warning produced)
- [x] 12.5 Unit tests for the eight built-in themes loading without diagnostics
- [x] 12.6 Bridge integration test: theme switch via `refreshCompiledConfig` keeps a running session alive
- [x] 12.7 Bridge static check: `ghostty_config_load_default_files` is never referenced in `Sources/OmuxTerminalBridge`
- [x] 12.8 GC test: stale generated files removed; active file preserved
Deferred with the explicit-reload scope reduction above.

## 13. Verification

- [x] 13.1 `make verify` passes (build + tests + linters as configured)
- [x] 13.2 `make smoke` passes with the runtime-enabled launch smoke test exercising the new config path
- [x] 13.3 Verify engine background matches active theme `bg.canvas` for the bundled themes
- [x] 13.4 Verify `omux config doctor` reports the expected collision warning when `[ghostty] background` and an active theme both define a background
- [x] 13.5 Verify explicit config reload preserves a running session across theme refresh
