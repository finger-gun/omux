## Why

`omux theme` currently prints numbered themes and asks the user to type a number or name. That works for scripts, but it is clumsy for a terminal-first CLI where choosing a theme is naturally an interactive terminal action.

Adding arrow-key selection makes theme switching feel native while preserving the existing name/number behavior for automation and non-interactive use.

## Goals

- Let users run `omux theme` in an interactive terminal, move through available themes with arrow keys, and press Enter to apply the highlighted theme.
- Keep `omux theme <name>`, `omux theme list`, and typed name/number selection working for scripts and non-TTY contexts.
- Keep the picker local, lightweight, and dependency-free.
- Avoid any changes to OpenMUX theme loading, the libghostty bridge, RPC contracts, keyboard handling inside terminal panes, or theme file format.

## Non-goals

- Do not add a full-screen TUI framework or external dependency.
- Do not change theme discovery, theme compilation, or generated Ghostty config behavior.
- Do not change AppKit terminal input, Option/Alt semantics, dead keys, compose keys, or IME behavior.
- Do not make the CLI require an interactive terminal for theme selection.

## What Changes

- `omux theme` uses an arrow-key picker when stdin/stdout are TTYs.
- Up/Down arrow keys move the highlighted theme; Enter applies it.
- `q`, Escape, or Ctrl-C cancel without modifying config.
- Non-interactive use falls back to the current prompt that accepts a typed number or theme name.
- Tests cover both the preserved fallback path and the new interactive-selection path through an injectable picker seam.

## Capabilities

### New Capabilities

- `theme-cli`: User-facing CLI behavior for listing and selecting OpenMUX themes.

### Modified Capabilities

- None.

## Impact

- Affected code: `Sources/OmuxCLI/OmuxCLI.swift`, `Tests/OmuxCLITests/OmuxCLITests.swift`, and CLI documentation.
- APIs: No JSON-RPC, hook, plugin, or libghostty bridge API changes.
- Dependencies: No new dependency.
- Performance: No startup impact; the picker runs only while `omux theme` waits for user input.
- Keyboard/input: This affects only CLI stdin in raw mode for the picker. It does not touch terminal-pane key handling, ISO/EU layout handling, Option semantics, dead keys, compose keys, or IME integration.
