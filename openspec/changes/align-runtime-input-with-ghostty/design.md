## Context

OpenMUX embeds Ghostty behind `OmuxTerminalBridge` and hosts runtime-backed terminal panes inside an AppKit-first shell. The embedded Ghostty API does not expose raw `NSEvent` pass-through; hosts must call structured APIs such as `ghostty_surface_key`, `ghostty_surface_text`, `ghostty_surface_preedit`, and `ghostty_surface_mouse_*`. That means OpenMUX needs an AppKit adapter, but the adapter should be behavioral glue rather than an independent terminal input engine.

The current adapter normalizes every key into `NormalizedKeyEvent`, classifies any Command-modified input as `.shortcut`, and has an empty `doCommand(by:)`. This can swallow terminal-owned AppKit text commands such as `Cmd+Backspace` and `Option+Backspace`. Ghostty's own macOS app already demonstrates mature AppKit adapter behavior for modifier translation, `performKeyEquivalent`, `doCommand`, `NSTextInputClient`, IME/preedit, and selection. OpenMUX should use that as behavioral inspiration while preserving clean-room implementation and OpenMUX ownership of shell behavior.

## Goals / Non-Goals

**Goals:**

- Intercept only explicit OpenMUX-owned shortcuts in runtime-backed terminal panes.
- Forward unclaimed keyboard input to Ghostty's runtime input path with correct keycode, modifier, text, composition, and consumed-modifier facts.
- Prevent AppKit text-command selectors from being silently swallowed.
- Expose Ghostty-owned terminal selection through OpenMUX-native bridge abstractions where AppKit asks for selection text/ranges.
- Add regression coverage for modified Backspace, terminal-owned Command chords, preedit, and selection visibility.

**Non-Goals:**

- Do not copy Ghostty macOS Swift implementation into OpenMUX.
- Do not adopt Ghostty's window, tab, split, config, update, or app-shell behavior.
- Do not synthesize terminal editing shortcuts in OpenMUX when Ghostty can represent the original key event.
- Do not expose `CGhostty` or raw Ghostty types outside `OmuxTerminalBridge`.

## Decisions

1. **Use an explicit OpenMUX shortcut classifier.**

   Runtime-backed input should identify only known OpenMUX shell shortcuts as OpenMUX-owned. A Command modifier alone is not a shortcut. This avoids swallowing terminal-owned chords such as `Cmd+Backspace`.

   Alternative considered: continue treating all Command chords as shortcuts. This was rejected because it blocks valid terminal behavior and AppKit text commands.

2. **Keep Ghostty as terminal input authority.**

   OpenMUX will avoid semantic mappings such as `Option+Backspace -> Ctrl+W`. Instead, modified keys should reach `ghostty_surface_key` with the original physical key and modifier facts so Ghostty's encoder and bindings determine behavior.

   Alternative considered: special-case known broken shortcuts. This was rejected because it would create a growing OpenMUX terminal-key compatibility layer.

3. **Handle AppKit text commands by re-entering the terminal key path where appropriate.**

   `interpretKeyEvents` can translate modified keys into `doCommand` selectors. The runtime host view should track the active event and, for unclaimed terminal events, fall back to Ghostty key dispatch rather than swallowing the selector.

   Alternative considered: implement selector-specific shell editing actions. This was rejected because text editing semantics belong to the terminal runtime.

4. **Expose selection via OpenMUX-native bridge values.**

   The bridge can read Ghostty selection through `ghostty_surface_read_selection`, translate it into a simple OpenMUX-native selection snapshot, and let the AppKit host view answer `selectedRange` and `attributedSubstring` without leaking Ghostty types.

   Alternative considered: keep returning empty selection ranges. This was rejected because AppKit selection integrations then cannot observe runtime-owned terminal selection.

5. **Treat Ghostty macOS adapter behavior as a reference, not a dependency.**

   OpenMUX should mirror behavior classes: modifier translation via Ghostty, original-event preservation where needed, AppKit text input composition, and Ghostty-owned selection. It should not copy source or inherit Ghostty app-shell assumptions.

## Risks / Trade-offs

- **Risk: Some Command chords intended for AppKit menus may reach Ghostty.** -> Use an explicit OpenMUX shortcut allowlist and keep standard menu commands wired through responder actions such as copy/paste/select all.
- **Risk: `doCommand` fallback may duplicate key dispatch.** -> Track the active keyDown event and dispatch through one path, with tests for Backspace variants and normal text.
- **Risk: Selection APIs may be unavailable in fallback/runtime test doubles.** -> Keep selection optional and return empty values when no runtime selection exists.
- **Risk: Clean-room alignment with Ghostty may drift as Ghostty evolves.** -> Document the behavioral contract and add regression tests for the user-visible cases we rely on.

## Migration Plan

1. Add explicit OpenMUX shortcut classification for runtime terminal input.
2. Adjust runtime key handling so non-OpenMUX Command chords and AppKit text-command selectors reach Ghostty.
3. Add OpenMUX-native selection snapshot support in the terminal bridge and runtime host view.
4. Add regression tests for modified Backspace and selection.
5. Update input specs and development docs with the new ownership model.

Rollback is straightforward: restore broad Command shortcut classification and empty selection behavior, but that would reintroduce the known input fidelity issues.

## Open Questions

- Should a later change introduce a reusable internal `GhosttyAppKitInputAdapter` type to make the runtime host view smaller?
- Should future verification include a manual matrix comparing OpenMUX and standalone Ghostty for a broader set of keyboards and IMEs before every release?
