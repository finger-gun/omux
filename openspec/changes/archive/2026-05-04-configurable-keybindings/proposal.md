## Why

OpenMUX shortcuts are currently hardcoded in the AppKit menu layer and input classifier, so users cannot adapt shell-owned key chords to their layout, habits, or terminal workflow. Configurable single-chord keybindings make the terminal workspace more open and hackable while keeping keyboard interception explicit and safe.

## Goals

- Add a user-facing `[keys]` config table for binding existing OpenMUX shell actions to single key chords.
- Support unbinding default shortcuts with `"none"` so unwanted shell chords, such as a destructive Backspace chord, can remain terminal-owned.
- Keep defaults useful and discoverable without requiring configuration.
- Make `omux config init` generate a complete config template containing all current defaults, including default keybindings.
- Preserve international keyboard correctness by avoiding broad interception and keeping Option/right-Option, dead keys, compose input, and IME flows terminal-owned unless a binding is explicitly safe.
- Keep the feature terminal-first and lightweight: no background service, browser surface, or plugin runtime is needed.

## Non-goals

- Do not add Helix-style modal keymaps, leader sequences, or multi-key chord state machines in this change.
- Do not bind arbitrary shell commands, macros, or plugins to keys yet.
- Do not expose libghostty-specific keybinding configuration as the primary OpenMUX API.
- Do not make Option-based bindings part of the default shortcut set.

## What Changes

- Add a `[keys]` TOML table where keys are chord strings and values are action identifiers or `"none"`.
- Add a typed keybinding model for known OpenMUX actions such as pane-tab create/close/navigation, pane navigation/removal, pane splitting, workspace create/close/switching, and sidebar toggle.
- Let user bindings override default bindings, including explicit unbinds.
- Update `omux config init` so newly generated configs include all documented defaults rather than sparse commented examples.
- Update shortcut classification so shell-owned shortcuts come from the effective keybinding registry instead of a fixed hardcoded list.
- Update AppKit menu key equivalents from the same effective registry where AppKit can represent the configured chord.
- Validate unknown actions, malformed chords, duplicate effective chords, and unsafe bindings with config diagnostics.
- Preserve terminal ownership for unbound chords, unknown Command chords, Option/right-Option text input, dead keys, and compose/IME input.

## Capabilities

### New Capabilities

- `keybinding-config`: User-configurable OpenMUX keybinding table, action identifiers, chord parsing, defaults, overrides, and unbinds.

### Modified Capabilities

- `config-system`: Add `[keys]` table decoding, validation, diagnostics, config template/docs, and preservation through config rewrites.
- `input-pipeline`: Replace fixed structural shortcut allowlisting with the effective keybinding registry while preserving terminal-owned input guarantees.
- `macos-app-shell`: Drive native menu key equivalents from effective keybindings where representable.

## Impact

- Affected code: config parser/loader/template, key input model, AppKit menu setup, configuration coordinator, tests, and documentation.
- APIs: adds stable OpenMUX action identifiers in config; no JSON-RPC or CLI contract is required for v1 keybinding configuration.
- Keyboard/input: high impact; must explicitly preserve ISO/EU layouts, right-Option behavior, dead keys, compose input, and IME flows.
- Extension points: creates a future-compatible action namespace that can later support plugin or hook actions without adding them now.
- Terminal bridge: no libghostty bridge change; keybinding decisions stay in OpenMUX-native shell/input layers.
