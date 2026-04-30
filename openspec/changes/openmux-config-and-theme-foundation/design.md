## Context

OpenMUX today initializes the embedded `libghostty` engine in `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift` with:

```swift
let config = ghostty_config_new()
ghostty_config_finalize(config)
```

Nothing is loaded between those two calls, so the engine runs on its compiled-in defaults. In parallel, `Sources/OmuxAppShell/WorkspaceTheme.swift` defines four hand-coded `WorkspaceShellTheme` Swift constants (`openMUXDark`, `catppuccin`, `gruvbox`, `sonokai`) used by the AppKit shell, but those constants never reach the engine. The two layers are visually disconnected.

The public `libghostty` C API (see `Vendor/ghostty/include/ghostty.h`) gives us:

- `ghostty_config_new`, `ghostty_config_clone`, `ghostty_config_free`
- `ghostty_config_load_file(config, path)` — the only string-input loader
- `ghostty_config_load_default_files(config)` — reads the user's Ghostty config; deliberately not used here
- `ghostty_config_load_cli_args` — argv-style injection
- `ghostty_config_finalize(config)`
- `ghostty_config_diagnostics_count` and `ghostty_config_get_diagnostic`
- `ghostty_app_update_config(app, config)` — live app-level reload
- `ghostty_surface_update_config(surface, config)` — live per-surface reload (deferred)

There is no `ghostty_config_load_string`. Any config we want the engine to consume must reach it via a file path or via argv. This shapes several decisions below.

OpenMUX also has an explicit architectural rule from `terminal-bridge` and `AGENTS.md`: `libghostty` types and calls stay confined to `OmuxTerminalBridge`. The rest of the codebase deals in OpenMUX-native concepts.

## Goals / Non-Goals

**Goals:**
- Establish OpenMUX as the owner of the user's terminal experience: one config file, one theme model, one compiler.
- Make the engine actually reflect OpenMUX themes, replacing the current "Ghostty defaults + disconnected shell colors" state.
- Keep the `libghostty` boundary intact: no new Ghostty types leak into shell or CLI code.
- Provide a permanent power-user escape hatch via `[ghostty]` pass-through so users are never blocked on first-class settings.
- Make the entire pipeline inspectable: TOML in, generated Ghostty file on disk, diagnostics out.
- Ship eight built-in themes that stress the token vocabulary in practice (a default, a multi-tone scheme, a dark-only set, and a light/dark pair).

**Non-Goals:**
- Light/dark auto-resolution driven by macOS appearance.
- Per-pane theme overrides via `ghostty_surface_update_config`.
- A keybindings system. That belongs with `input-pipeline` and gets EU-layout / Option / dead-key treatment in its own change.
- Runtime `omux import ghostty` / `omux export ghostty` commands.
- Honoring Ghostty actions (`PWD`, `COMMAND_FINISHED`, etc.). Captured in `docs/research/ghostty-action-dispatch.md`.
- Theme inheritance (`extends`) or runtime derivation rules. Every shipped theme is fully populated.

## Decisions

### D1. Config file format and location

`~/.omux/config.toml`. Single file. TOML.

- **Why TOML over JSON or YAML:** TOML is the most ergonomic format for hand-edited app configuration, has a small spec, and avoids YAML's indentation footguns. It also matches the format of `pyproject.toml` and `Cargo.toml` that developers (the target audience) already hand-edit.
- **Why `~/.omux/` over `~/.config/omux/` (XDG) or `~/Library/Application Support/OpenMUX/`:** The user explicitly chose simplicity. `~/.omux/` keeps user-edited config, user themes, and OpenMUX-managed generated artifacts in one discoverable place, and it matches the dotfile conventions of the target audience. macOS sandboxing is not a concern for v1 (we ship outside the App Store).
- **Layout:**
  ```
  ~/.omux/
  ├─ config.toml                     # user-edited
  ├─ themes/                         # user theme overrides + custom themes
  │  └─ <name>.toml
  └─ generated/
     └─ ghostty/
        └─ config-<hash>             # OpenMUX-managed; user SHOULD NOT edit
  ```

**Alternatives considered:** `~/.config/omux/` (XDG-strict) was rejected for reasons above. Application Support was rejected because users need to hand-edit `config.toml` and grep dotfile repos for it. JSON was rejected for hand-editing UX. YAML was rejected for indentation fragility.

### D2. TOML parser

Use a vendored Swift TOML parser as a Swift Package Manager dependency. Specific package selection is left to implementation, but the candidate is `swift-toml` or an equivalent maintained pure-Swift parser. Constraints:

- Pure Swift, no system C deps.
- Support TOML 1.0.
- Permissive license compatible with Apache-2.0.

If no maintained option meets the bar, fall back to a small in-tree subset parser limited to the syntax we actually use (tables, sub-tables, strings, integers, booleans, arrays of strings). The in-tree parser is the contingency, not the plan.

**Alternative considered:** Hand-roll from the start. Rejected because TOML 1.0 is small but has enough edge cases (multi-line strings, datetimes, inline tables) that getting them subtly wrong would surface as user-confusing parse errors.

### D3. Schema versioning

`config.toml` MUST carry a top-level `schema = N` integer. Initial value: `schema = 1`. The loader rejects unknown future versions with a clear diagnostic ("OpenMUX X.Y understands schema N; this file is schema M; upgrade or downgrade OpenMUX"). When schema bumps occur, a one-shot migration path runs at load time and writes the migrated file back, preserving comments where the parser allows.

For v1 there are no migrations to write. The mechanism exists so future changes are non-breaking.

**Alternative considered:** No schema field; treat the loader as version-agnostic. Rejected — config files outlive the OpenMUX builds that wrote them; a missing version field is a debt we will regret on the first incompatible change.

### D4. Token vocabulary (the contract that lives in the spec)

The full token set, fixed for v1. Every built-in theme MUST set every token. The compiler maps tokens to two consumers — AppKit shell colors and Ghostty config text — exactly once.

```
   Surface tokens (chrome + terminal background)
   ────────────────────────────────────────────────
   bg.canvas              # main terminal area background
   bg.surface             # pane card / chrome backdrop
   bg.elevated            # sidebar, top bar, pane headers

   Text tokens
   ────────────────────────────────────────────────
   fg.primary             # main foreground; also Ghostty `foreground`
   fg.secondary           # sidebar labels, secondary chrome text
   fg.muted               # timestamps, hints, disabled chrome

   Border tokens
   ────────────────────────────────────────────────
   border.subtle          # subdued chrome dividers
   border.strong          # active borders, focus boundary

   Accent
   ────────────────────────────────────────────────
   accent                 # focus ring, active tab, selection chrome

   Terminal-only tokens
   ────────────────────────────────────────────────
   cursor                 # Ghostty `cursor-color`
   cursor.text            # Ghostty `cursor-text` (text under block cursor)
   selection.bg           # Ghostty `selection-background`
   selection.fg           # Ghostty `selection-foreground`

   ANSI palette (16 tokens)
   ────────────────────────────────────────────────
   ansi.black,   ansi.red,    ansi.green,   ansi.yellow
   ansi.blue,    ansi.magenta, ansi.cyan,   ansi.white
   ansi.brightBlack,   ansi.brightRed,    ansi.brightGreen,   ansi.brightYellow
   ansi.brightBlue,    ansi.brightMagenta, ansi.brightCyan,   ansi.brightWhite
```

That is **30 tokens** total. All are required hex colors of the form `#rrggbb` or `#rrggbbaa`.

**Token-to-Ghostty mapping:**

| Token | Ghostty key |
| --- | --- |
| `bg.canvas` | `background` |
| `fg.primary` | `foreground` |
| `cursor` | `cursor-color` |
| `cursor.text` | `cursor-text` |
| `selection.bg` | `selection-background` |
| `selection.fg` | `selection-foreground` |
| `ansi.black` ... `ansi.brightWhite` | `palette = 0=...` ... `palette = 15=...` |
| `bg.surface`, `bg.elevated`, `fg.secondary`, `fg.muted`, `border.*`, `accent` | (no Ghostty mapping; AppKit-only) |

**Alternative considered:** A larger or smaller token set. Smaller (e.g., merging `border.subtle`/`border.strong`) reintroduces derivation. Larger (separate `pane.header.bg`, `tab.active.bg`, etc.) bloats every theme file with redundant values. 30 is the smallest set that lets the AppKit shell and Ghostty render coherently.

### D5. Theme file format

Flat TOML, one theme per file:

```toml
schema = 1
name        = "monokai-soda"
displayName = "Monokai Soda"

[tokens]
"bg.canvas"   = "#1a1a1a"
"bg.surface"  = "#222222"
# ... all 30 tokens
```

No `extends`. No derivation. Loader fails fast if a token is missing, with a diagnostic that names the missing token. Built-in themes ship as Swift package resources under the `OmuxTheme` target; user themes are loaded from `~/.omux/themes/<name>.toml`. Same-name conflicts: user theme wins, with a diagnostic.

### D6. Compiler output and on-disk layout

The compiler emits a deterministic Ghostty config text file at:

```
~/.omux/generated/ghostty/config-<hash>
```

The hash is `sha256` of the canonicalized inputs, truncated to 16 hex chars:

```
   hash = sha256(
       schema_version
       || OpenMUX build version
       || resolved_token_table_in_canonical_order
       || sorted_passthrough_keys_and_values
       || sorted_omux_managed_keys_and_values
   )[0..16]
```

**Properties:**
- Same logical config → same file → same path. Cache hits are free.
- Stale files older than N days (or older than the current OpenMUX version) get garbage collected on launch. Concrete N is left to implementation; suggest 14 days.
- The OpenMUX version is part of the hash so an OpenMUX upgrade that changes how a token compiles produces a fresh artifact.

**File contents emit order (last-write-wins is the override mechanism):**

```
   1. # Header comment with hash, OpenMUX version, theme name, generation timestamp
   2. # === [ghostty] pass-through ===
   3. <pass-through keys, sorted>
   4. # === OpenMUX-managed ===
   5. <theme tokens compiled to Ghostty keys, in canonical order>
   6. <font, scrollback, and other OMUX-derived keys>
```

Emitting OMUX-managed keys last is the entire override mechanism. Ghostty's parser keeps the last value seen.

**Alternative considered:** Use `ghostty_config_load_cli_args` to inject configuration as argv-equivalent strings, avoiding the on-disk file entirely. Deferred — the public C API does not document the argv format clearly and the file-based path is what the official Ghostty macOS host uses. We can revisit if the on-disk approach causes friction.

### D7. The `[ghostty]` pass-through and OMUX-managed key list

`[ghostty]` is a flat top-level TOML table. Every key under it is forwarded into the generated Ghostty config text in step 3 of the emission order above. No interpretation, no validation against an allowlist.

Conflicts with OMUX-managed keys are resolved by emit order (OMUX wins) and are reported through `omux config doctor` and the launch-time diagnostic stream.

The **OMUX-managed key list** is the canonical answer to "which Ghostty keys does OpenMUX overwrite?" For v1:

```
   background, foreground
   cursor-color, cursor-text
   selection-background, selection-foreground
   palette                            (all 16 entries)
   font-family, font-size             (when set in OMUX config)
   scrollback-limit                   (when set in OMUX config)
```

This list lives in code as the source of truth. The spec describes it by category. When OpenMUX adds a first-class setting in a future change, the new key joins this list and starts overriding pass-through automatically.

**No blocklist.** App-shell keys like `window-decoration`, `quick-terminal-position`, etc. are either ignored by libghostty in embedded mode or trigger actions that our `action_cb: { _, _, _ in false }` already rejects. No additional gate is required.

**Alternative considered:** Hard-error on app-shell keys. Rejected — speculative; we have no evidence such keys actually break embedded libghostty, and rejecting them eagerly creates spec drift every time Ghostty adds new app-shell keys.

### D8. Bridge boundary changes

`OmuxTerminalBridge` gains a small new surface. Outside of bridge code, this remains opaque.

```
   bridge.applyCompiledConfig(path: URL) throws -> [Diagnostic]
   bridge.refreshCompiledConfig(path: URL) throws -> [Diagnostic]
```

- `applyCompiledConfig` is called once during bridge initialization. It replaces the current `ghostty_config_finalize(blank)` flow with `load_file → finalize → ghostty_app_new`.
- `refreshCompiledConfig` is called on live reload. It builds a new config object, finalizes it, calls `ghostty_app_update_config`, and frees the old config.
- `Diagnostic` is an OpenMUX-native struct holding severity, message, file path, and line where available. Internally it wraps `ghostty_config_diagnostics_count` / `ghostty_config_get_diagnostic` plus our own validation errors.

Bridge MUST NOT call `ghostty_config_load_default_files`. This is a one-line guarantee enforced by code review and by a unit test that grep-scans the bridge module for the symbol.

### D9. Live reload trigger

File watch over:
- `~/.omux/config.toml`
- `~/.omux/themes/*.toml` (only the active theme matters; others are ignored unless the active theme name changes)

Implementation: Apple's `DispatchSource.makeFileSystemObjectSource` for the directory, with a debounced (250 ms) recompile pass. If the recompile produces a new hash, write the new generated file and call `bridge.refreshCompiledConfig(path)`. If recompile fails validation, log diagnostics and keep the previous successful config.

`omux config reload` is an explicit CLI trigger that bypasses the file watch — useful in scripted contexts or when the watcher is unreliable on networked filesystems.

**Alternative considered:** `FSEvents` directly. Rejected for v1; `DispatchSource` is sufficient for single-user dotfiles.

### D10. AppKit shell renderer refactor

`Sources/OmuxAppShell/WorkspaceTheme.swift` is reshaped:

- The four hardcoded `WorkspaceShellTheme` constants are removed.
- `WorkspaceShellColors` becomes a value type computed from a `ResolvedThemeTokens` value supplied by `OmuxTheme`.
- The shell subscribes to theme changes from `OmuxTheme` (live reload) and re-renders chrome with the new tokens.

Token-to-NSColor mapping for the AppKit consumer (canonical):

| AppKit field | Token |
| --- | --- |
| `windowBackground` | `bg.surface` |
| `sidebarBackground`, `topBarBackground`, `paneHeaderBackground` | `bg.elevated` |
| `canvasBackground` | `bg.canvas` |
| `paneCardBackground` | `bg.surface` |
| `chromeButtonBackground` | derived in code: `bg.elevated` |
| `chromeButtonActiveBackground` | derived in code: `bg.elevated` blended toward `accent` (this is renderer-side styling, not token derivation; the *tokens* never derive from each other) |
| `border`, `subduedBorder` | `border.strong`, `border.subtle` |
| `accent` | `accent` |
| `selection` | `selection.bg` |
| `textPrimary`, `textSecondary`, `textMuted` | `fg.primary`, `fg.secondary`, `fg.muted` |

Chrome button hover/active tints are AppKit rendering concerns, not tokens. Keeping that line clear is what prevents the token vocabulary from sprawling.

### D11. Built-in themes shipping as data

Built-in themes ship as TOML files in the `OmuxTheme` Swift package target's `Resources/themes/` directory and are loaded via `Bundle.module`. They are NOT compiled into Swift source. This makes them:

- Diffable in PRs.
- Easy to swap/iterate without recompiling.
- Trivially exportable (the same file format users author).

Initial set: `monokai-soda.toml` (default), `catppuccin.toml`, `dracula.toml`, `nord.toml`, `gruvbox.toml`, `one-dark.toml`, `solarized-dark.toml`, `solarized-light.toml`.

### D12. iTerm2 importer (dev-time only)

A standalone Swift script under `Scripts/import-iterm2.swift` (or a small SPM executable target) takes a `.itermcolors` file plus a target chrome palette (defaulting to a "neutral dark" or "neutral light" depending on whether the source is dark or light) and emits a fully-populated OpenMUX theme TOML. The output is a static file we commit.

The importer is **not** invoked at OpenMUX runtime. Users in v1 cannot run `omux theme import` — that becomes a runtime command in a later change.

For the initial eight themes:
- `monokai-soda`, `catppuccin`, `dracula`, `nord`, `gruvbox`, `one-dark`: imported via the script, then chrome tokens hand-tuned where the auto-mapping looks off.
- `solarized-dark`, `solarized-light`: imported via the script.

Chrome derivation rules used at import time (NOT part of the spec, NOT applied at runtime; these are import heuristics that a human reviewer can override before commit):
- `bg.surface = bg.canvas` lightened ~3% for dark themes, darkened ~3% for light themes.
- `bg.elevated = bg.canvas` lightened ~6% for dark, darkened ~6% for light.
- `fg.secondary = mix(fg.primary, bg.canvas, 0.65, 0.35)`.
- `fg.muted = mix(fg.primary, bg.canvas, 0.45, 0.55)`.
- `border.subtle = mix(fg.primary, bg.canvas, 0.12, 0.88)`.
- `border.strong = mix(fg.primary, bg.canvas, 0.25, 0.75)`.
- `accent = ansi.blue` for most schemes; overridden when the scheme has a clear identity color (Catppuccin: mauve; Dracula: purple; Gruvbox: aqua; etc.).

### D13. Module placement

```
   Sources/
   ├─ OmuxConfig/                    NEW. TOML parsing, schema versioning,
   │                                 file discovery, diagnostics, [ghostty]
   │                                 pass-through extraction.
   │
   ├─ OmuxTheme/                     NEW. Token vocabulary, theme TOML
   │                                 parsing, theme registry, compiler from
   │                                 tokens to Ghostty config text, generated
   │                                 file management, hash, GC. Resources/
   │                                 holds the eight built-in themes.
   │
   ├─ OmuxTerminalBridge/            MODIFIED. Adds applyCompiledConfig and
   │                                 refreshCompiledConfig. Replaces
   │                                 finalize-on-blank with load_file flow.
   │
   ├─ OmuxAppShell/                  MODIFIED. WorkspaceTheme.swift becomes
   │                                 a token consumer. Subscribes to live
   │                                 reload.
   │
   └─ omux / OmuxCLI/                MODIFIED. Adds `omux config doctor` and
                                     `omux config reload`.
```

`OmuxConfig` and `OmuxTheme` are independent of `OmuxTerminalBridge` — they don't import any Ghostty types. The bridge consumes a path produced by `OmuxTheme`.

## Risks / Trade-offs

- **[Risk] TOML parser dependency ages or goes unmaintained.** → Mitigation: keep the parser surface narrow (tables, strings, ints, bools, arrays); the in-tree subset parser is a 1-day fallback. Vendor pin to a specific version.
- **[Risk] `libghostty` config text format drifts on upgrade.** → Mitigation: the compiler is the only place that knows Ghostty key syntax; one file to update. The pinned vendored Ghostty version (per `terminal-bridge`) means drift is a deliberate event, not surprise.
- **[Risk] Stale generated files accumulate under `~/.omux/generated/`.** → Mitigation: GC at launch by mtime and by build-version. Cap directory size.
- **[Risk] File watcher is flaky on networked or sync filesystems (iCloud, Dropbox-managed dotfiles).** → Mitigation: `omux config reload` is the explicit fallback. Watcher failure logs a diagnostic instead of silently breaking.
- **[Risk] Live reload races: file written half-way when watcher fires.** → Mitigation: 250 ms debounce; the recompile pipeline is atomic and never replaces the active config until the new one validates.
- **[Risk] Hash collisions cause two distinct configs to share a generated file.** → Mitigation: 16 hex chars of sha256 = 64 bits; collision probability is negligible at the scale of one user's machine. If observed, increase to 24 chars; not worth it preemptively.
- **[Risk] iTerm2 import produces ugly chrome for some schemes.** → Mitigation: chrome tokens are reviewed and hand-tuned in PR before commit; the eight built-ins are the curated set, not the raw output of the script.
- **[Risk] Users hand-edit `~/.omux/generated/ghostty/config-*` and lose changes on reload.** → Mitigation: header comment in every generated file declares the path is OpenMUX-managed; documentation states it explicitly; live reload always overwrites.
- **[Trade-off] No theme inheritance.** → Every theme is fully populated. Eight themes means eight ~50-line files. This is a real authoring cost we accept in exchange for a flat, debuggable runtime. Inheritance can be added later as pure addition.
- **[Trade-off] No light/dark auto-resolution.** → Users pick a theme by name. Solarized ships as two siblings instead of one auto-switching theme. Can be added as a thin layer over the existing theme system later.
- **[Trade-off] No per-pane overrides.** → All panes share one theme. `surface_update_config` is real and supported by the engine, but plumbing it through the workspace/pane model is its own change.

## Migration Plan

This is a foundation change with no prior config or theme storage to migrate from. Steps:

1. Land `OmuxConfig`, `OmuxTheme`, the eight built-in theme files, and the importer script. Existing OpenMUX code paths still work (engine still on defaults, shell still uses hardcoded constants).
2. Switch the bridge from blank-config-finalize to `applyCompiledConfig(path)`. Engine now reflects the active theme.
3. Switch `WorkspaceTheme.swift` from hardcoded constants to a token consumer. Shell now reflects the active theme.
4. Wire the file watcher and `omux config reload`.
5. Remove the four hardcoded `WorkspaceShellTheme` constants. The new built-in set is authoritative.

Rollback strategy: each step is independently revertable. If a step regresses, revert that commit; the previous step's behavior is functional on its own (engine on defaults but shell themed, or engine themed but shell on hardcoded constants). The bridge change in step 2 is the only step where a regression affects every user — it gets a smoke test on CI before merge.

First-run behavior when `~/.omux/config.toml` does not exist: OpenMUX uses built-in defaults (`theme = "monokai-soda"`, no pass-through, no font override) and does NOT auto-create a config file. A first-run hint surfaces in the app menu / `omux` CLI suggesting `omux config init` (the `init` subcommand is in scope for this change) to scaffold a documented starter file.

## Open Questions

- **TOML parser package selection.** Concrete pick (e.g., `swift-toml` vs alternative) is left to the implementer; criteria are listed under D2. If no candidate meets the bar, the in-tree subset parser becomes the implementation.
- **Generated-file GC cadence.** Suggested 14 days; finalize during implementation based on actual file sizes and reload frequency.
- **Where does `omux config init` live in the CLI surface?** `omux config init` vs `omux init config` vs `omux config new` — surface decision deferred to CLI implementation.
- **Should `omux config doctor` exit non-zero on collisions?** Default proposal: exit 0 on collisions (they are warnings); exit non-zero on hard errors (parse failure, missing tokens, schema mismatch). Confirm during implementation.
