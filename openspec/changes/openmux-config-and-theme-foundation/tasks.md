## 1. OmuxConfig module foundation

- [ ] 1.1 Add a new `OmuxConfig` Swift package target under `Sources/OmuxConfig/`
- [ ] 1.2 Add a TOML parser dependency to `Package.swift` (per design D2; confirm package selection during implementation; fall back to in-tree subset parser if no candidate meets the bar)
- [ ] 1.3 Define `OmuxConfigSchemaVersion` constant (= 1) and the `OmuxConfig` value type covering `[theme]`, `[terminal]`, and `[ghostty]` sections
- [ ] 1.4 Define `OmuxConfigDiagnostic` (severity, message, file, line) as the OpenMUX-native diagnostic struct shared with the bridge
- [ ] 1.5 Implement schema-version handling: reject missing `schema`, reject unknown future versions, hook for future migrations
- [ ] 1.6 Implement layered defaults: documented built-in defaults overlaid by user file values
- [ ] 1.7 Implement `[ghostty]` pass-through extraction as an ordered key/value list (not interpreted)
- [ ] 1.8 Implement file location resolution at `~/.omux/config.toml` with absent-file handling that runs on defaults

## 2. OmuxTheme module foundation

- [ ] 2.1 Add a new `OmuxTheme` Swift package target under `Sources/OmuxTheme/`
- [ ] 2.2 Define the closed token vocabulary (30 tokens per design D4) as a strongly-typed enum or struct keyed set
- [ ] 2.3 Define `Theme` value type: `name`, `displayName`, `tokens: [Token: Color]`, `schema`
- [ ] 2.4 Implement theme TOML parser that fails fast on unknown tokens, missing tokens, or `extends`-like keys
- [ ] 2.5 Implement theme registry that loads built-ins from `Bundle.module` and user themes from `~/.omux/themes/*.toml`, with user-wins-on-conflict + warning diagnostic
- [ ] 2.6 Define `ResolvedThemeTokens` value type exported for the AppKit shell consumer

## 3. Built-in themes (data files)

- [ ] 3.1 Create `Sources/OmuxTheme/Resources/themes/` and declare it as a package resource in `Package.swift`
- [ ] 3.2 Build/curate `monokai-soda.toml` (default; full 30-token population)
- [ ] 3.3 Build/curate `catppuccin.toml`
- [ ] 3.4 Build/curate `dracula.toml`
- [ ] 3.5 Build/curate `nord.toml`
- [ ] 3.6 Build/curate `gruvbox.toml`
- [ ] 3.7 Build/curate `one-dark.toml`
- [ ] 3.8 Build/curate `solarized-dark.toml`
- [ ] 3.9 Build/curate `solarized-light.toml`

## 4. iTerm2 importer (dev-time tool)

- [ ] 4.1 Add a Swift script or executable target at `Scripts/import-iterm2/` (per design D12)
- [ ] 4.2 Parse `.itermcolors` plist → ANSI 16 + bg/fg/cursor/selection
- [ ] 4.3 Implement chrome-derivation heuristics for missing tokens (per design D12; output is a static file, derivation does NOT run at runtime)
- [ ] 4.4 Emit a fully-populated OpenMUX theme TOML to a destination path
- [ ] 4.5 Document usage in `Scripts/import-iterm2/README.md` so future themes can be added

## 5. Theme-to-Ghostty compiler

- [ ] 5.1 Implement token → Ghostty key mapping per design D4 (`bg.canvas` → `background`, ANSI palette → `palette = N=...`, etc.)
- [ ] 5.2 Implement OpenMUX-managed key list (per design D7) as the canonical override-source-of-truth
- [ ] 5.3 Implement compiled file emitter that writes pass-through keys first, OpenMUX-managed keys last (per spec: last-write-wins is the override mechanism)
- [ ] 5.4 Implement collision detection between `[ghostty]` pass-through and the OpenMUX-managed key list, producing warning diagnostics
- [ ] 5.5 Implement deterministic hash (sha256, 16 hex chars per design D6) over schema version, OpenMUX build, resolved tokens, sorted pass-through, sorted OMUX-managed keys
- [ ] 5.6 Implement header-comment generation (declaring OpenMUX ownership, source path, theme name, version, hash, no-edit notice)
- [ ] 5.7 Write generated file to `~/.omux/generated/ghostty/config-<hash>` atomically (write to temp, rename)

## 6. Generated-artifact lifecycle

- [ ] 6.1 Implement directory creation under `~/.omux/generated/ghostty/`
- [ ] 6.2 Implement garbage collection at launch (per spec; remove non-active files older than retention threshold or from a different OpenMUX build; cap directory size)
- [ ] 6.3 Ensure GC never deletes the file the running engine is currently using

## 7. Bridge boundary changes

- [ ] 7.1 Add `applyCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic]` to `GhosttyTerminalBridge` / `CGhosttyRuntime`
- [ ] 7.2 Replace blank-config initialization in `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift:79-80` with `ghostty_config_new` → `ghostty_config_load_file(path)` → `ghostty_config_finalize` flow
- [ ] 7.3 Translate `ghostty_config_diagnostics_count` / `ghostty_config_get_diagnostic` results into `OmuxConfigDiagnostic` values; return them upward
- [ ] 7.4 Add `refreshCompiledConfig(path: URL) throws -> [OmuxConfigDiagnostic]` that builds a new config object, finalizes, calls `ghostty_app_update_config`, and frees the previous config without recreating sessions
- [ ] 7.5 Add a unit test that grep-asserts the bridge module never references `ghostty_config_load_default_files`
- [ ] 7.6 Add a smoke test verifying that `applyCompiledConfig` with a known theme produces visible engine state matching the theme tokens (background, palette)

## 8. AppKit shell renderer refactor

- [ ] 8.1 In `Sources/OmuxAppShell/WorkspaceTheme.swift`, remove the four hardcoded `WorkspaceShellTheme` constants (`openMUXDark`, `catppuccin`, `gruvbox`, `sonokai`)
- [ ] 8.2 Convert `WorkspaceShellColors` into a value type computed from `ResolvedThemeTokens` (per design D10 mapping table)
- [ ] 8.3 Move chrome button hover/active tinting from token-derived to renderer-side blending of `bg.elevated` toward `accent`
- [ ] 8.4 Update every existing shell-theme call site (`WorkspaceWindowController`, `HostedTerminalPaneView` styling, etc.) to consume `ResolvedThemeTokens` from `OmuxTheme`
- [ ] 8.5 Subscribe the shell to theme-change events from `OmuxTheme` and re-render chrome on update

## 9. Live reload pipeline

- [ ] 9.1 Implement a debounced file watcher (250 ms) over `~/.omux/config.toml` and `~/.omux/themes/*.toml` using `DispatchSource.makeFileSystemObjectSource`
- [ ] 9.2 On file change: reload config → re-resolve theme → recompile → if hash changed, write new generated file → call `bridge.refreshCompiledConfig`
- [ ] 9.3 On reload validation failure: log diagnostics, do not change generated file, do not call bridge refresh; previous config stays active
- [ ] 9.4 Surface live-reload diagnostics through the same diagnostic stream used at launch

## 10. CLI surface

- [ ] 10.1 Add `omux config doctor` to `Sources/omux` / `Sources/OmuxCLI`: print all current diagnostics, exit zero on warnings-only, exit non-zero on hard errors
- [ ] 10.2 Add `omux config reload`: trigger the same recompile-and-apply pipeline as the file watcher, independent of watcher state
- [ ] 10.3 Add `omux config init`: scaffold a documented starter `~/.omux/config.toml` (refuse to overwrite if file exists; subcommand naming finalized during implementation per design open question)
- [ ] 10.4 Wire CLI commands through the existing `omux-control-plane` JSON-RPC where applicable so the running app handles reload, not the CLI binary alone

## 11. Documentation

- [ ] 11.1 Add a user-facing reference for the token vocabulary (table mapping tokens to AppKit role and Ghostty key)
- [ ] 11.2 Add a user-facing reference for the `[ghostty]` pass-through contract (no allowlist, OMUX-managed keys win, pass-through is not OpenMUX-versioned)
- [ ] 11.3 Update `docs/manifest.md` and `docs/development.md` with the new config and theme story
- [ ] 11.4 Update `docs/roadmap.md`: move "Theme system and built-in presets" status to reflect the token-based model; mark "Theme customization" item as covered by this change for the user-overrides part

## 12. Tests

- [ ] 12.1 Unit tests for `OmuxConfig` parsing (schema mismatch, unknown keys, partial files, `[ghostty]` extraction)
- [ ] 12.2 Unit tests for `OmuxTheme` parsing (missing token, unknown token, `extends` rejection, user-wins-on-conflict)
- [ ] 12.3 Unit tests for compiler determinism (same inputs → same hash → same output bytes)
- [ ] 12.4 Unit tests for compiler emit order (pass-through before OMUX-managed; collision warning produced)
- [ ] 12.5 Unit tests for the eight built-in themes loading without diagnostics
- [ ] 12.6 Bridge integration test: theme switch via `refreshCompiledConfig` keeps a running session alive
- [ ] 12.7 Bridge static check: `ghostty_config_load_default_files` is never referenced in `Sources/OmuxTerminalBridge`
- [ ] 12.8 GC test: stale generated files removed; active file preserved
- [ ] 12.9 Live-reload integration test: edit on disk triggers compile + apply within debounce window
- [ ] 12.10 Live-reload failure test: invalid edit preserves last good config

## 13. Verification

- [ ] 13.1 `make verify` passes (build + tests + linters as configured)
- [ ] 13.2 `make smoke` passes with the runtime-enabled launch smoke test exercising the new config path
- [ ] 13.3 Manual: confirm engine background matches active theme `bg.canvas` for all eight built-in themes
- [ ] 13.4 Manual: confirm `omux config doctor` reports the expected collision warning when `[ghostty] background` and an active theme both define a background
- [ ] 13.5 Manual: confirm live reload swaps theme without killing a long-running shell session (e.g., `vim` or `tmux`)
