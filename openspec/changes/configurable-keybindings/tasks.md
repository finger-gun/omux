## 1. Keybinding Model and Config

- [x] 1.1 Add typed keybinding actions, normalized chord parsing, and default binding definitions.
- [x] 1.2 Decode `[keys]` from config and validate malformed chords, unknown actions, duplicate chords, and unsafe Option bindings.
- [x] 1.3 Layer user `[keys]` entries over built-in defaults, including `"none"` unbinds.
- [x] 1.4 Update `omux config init` to generate a complete config with all current defaults and the full `[keys]` table.
- [x] 1.5 Preserve `[keys]` entries when config rewrite commands update theme or other settings.

## 2. Input and AppKit Integration

- [x] 2.1 Replace hardcoded shortcut allowlisting with the effective keybinding registry.
- [x] 2.2 Route configured keybinding actions to existing workspace, pane, pane-tab, sidebar, and navigation actions.
- [x] 2.3 Drive representable AppKit menu key equivalents from the effective keybinding registry.
- [x] 2.4 Apply keybinding reloads without restarting existing terminal sessions.
- [x] 2.5 Ensure `Cmd+Shift+Backspace` is not bound by default and remains terminal-owned.

## 3. Documentation and Tests

- [x] 3.1 Document `[keys]`, supported action identifiers, chord syntax, defaults, and `"none"` unbinding.
- [x] 3.2 Add config tests for parsing, defaults, invalid bindings, complete config init output, and rewrite preservation.
- [x] 3.3 Add input tests for default bindings, user overrides, unbound chords, and international/Option/composition preservation.
- [x] 3.4 Add app-shell tests for menu shortcut defaults, rebinding, unbinding, and reload behavior.

## 4. Validation

- [x] 4.1 Run OpenSpec validation for `configurable-keybindings` and `scope-shortcut-ladder`.
- [x] 4.2 Run targeted Swift tests for config, input, CLI/config init, and app-shell menu behavior.
- [x] 4.3 Run the full repository Swift test suite.
