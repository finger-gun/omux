## 1. Input Ownership

- [x] 1.1 Replace broad Command-modifier shortcut routing with an explicit OpenMUX shortcut allowlist in the normalized input pipeline.
- [x] 1.2 Update runtime-backed key handling so unclaimed Command chords and modified Backspace events continue to Ghostty runtime input.
- [x] 1.3 Remove or constrain OpenMUX semantic terminal-editing substitutions where Ghostty can handle the original key event.

## 2. AppKit Adapter Behavior

- [x] 2.1 Add `doCommand(by:)` fallback handling for terminal-owned text-command selectors produced by `interpretKeyEvents`.
- [x] 2.2 Preserve existing IME/preedit, dead-key, side-specific Option, and Ghostty modifier-translation behavior while changing dispatch.

## 3. Runtime Selection

- [x] 3.1 Add OpenMUX-native runtime selection read APIs at the bridge boundary without leaking Ghostty types.
- [x] 3.2 Back `RuntimeTerminalHostView.selectedRange()` and `attributedSubstring(forProposedRange:actualRange:)` with runtime-owned selection where available.

## 4. Tests and Documentation

- [x] 4.1 Add unit/regression tests for explicit shortcut classification, unknown Command chords, `Cmd+Backspace`, and `Option+Backspace`.
- [x] 4.2 Add tests for AppKit text-command fallback and runtime selection query behavior.
- [x] 4.3 Update development/input documentation to record the OpenMUX-gate/Ghostty-semantics ownership rule.
- [x] 4.4 Run targeted tests, `make verify`, and `openspec validate align-runtime-input-with-ghostty --strict`.

## 5. Selection Follow-up

- [x] 5.1 Refresh runtime pointer position before mouse button transitions so selection anchors use the current click location.
- [x] 5.2 Preserve drag-selection state when the pointer exits the runtime view while a button is still pressed.
- [x] 5.3 Run targeted pointer-selection tests, `make verify`, and `openspec validate align-runtime-input-with-ghostty --strict`.
