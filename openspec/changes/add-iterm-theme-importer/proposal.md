## Why

OpenMUX already has a token-owned theme model, but adding high-quality terminal color schemes currently requires hand-transcribing palette files into OpenMUX TOML. That slows down theme growth and makes it easy to introduce mistakes in a terminal-first surface where color fidelity and readable shell chrome matter.

This change adds a repeatable import path for selected themes from the iTerm2 Color Schemes catalog, keeping OpenMUX open and hackable while preserving its own deterministic theme schema instead of depending on Ghostty's runtime theme lookup.

## Goals

- Provide a scriptable importer that transforms upstream Ghostty-format iTerm2 Color Schemes files into OpenMUX theme TOML.
- Use a manifest so the selected imported themes, display names, source names, and output identifiers are inspectable and reproducible.
- Add recognizable built-in themes from the catalog using the importer.
- Keep imported output inside OpenMUX's existing theme registry and compiler path.
- Preserve terminal-first behavior by prioritizing exact terminal palette mapping and deterministic shell chrome token derivation.

## Non-goals

- Do not add a browser, webview, background service, or dynamic online theme browser.
- Do not make OpenMUX read the user's Ghostty config or Ghostty theme directories.
- Do not expose libghostty theme names or upstream theme internals across the OpenMUX codebase.
- Do not change keyboard/input behavior, keymaps, Option/Alt semantics, dead-key handling, or IME behavior.
- Do not import every upstream theme in this change.

## What Changes

- Add a repository script that fetches selected upstream Ghostty theme files from `mbadolato/iTerm2-Color-Schemes`, validates the expected color keys, and emits OpenMUX theme TOML files.
- Add a manifest for selected themes from the catalog.
- Add generated built-in theme resources for the selected themes.
- Update theme tests and documentation so the expanded bundled theme set is explicit.
- Record upstream source/ref information in generated files to support review and future refreshes.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `theme-system`: The built-in theme set gains an import pipeline and additional bundled presets generated from selected iTerm2 Color Schemes Ghostty files.

## Impact

- Affected code: `Scripts/`, `Sources/OmuxTheme/Resources/themes/`, `Tests/OmuxThemeTests/`, and theme-related documentation.
- APIs: No public CLI, RPC, hook, plugin, or libghostty bridge API changes.
- Dependencies: The importer should rely on standard macOS/POSIX tooling and Swift already present in the repo; it should not add a long-running service or package dependency.
- Performance: Runtime startup remains resource-bundle based. The importer runs only during development or maintenance and is not part of normal app startup.
- Keyboard/input: No impact; this change does not touch terminal input, AppKit key handling, ISO/EU layouts, Option semantics, dead keys, compose keys, or IME integration.
