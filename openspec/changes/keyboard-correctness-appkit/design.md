## Context

OpenMUX embeds libghostty behind `OmuxTerminalBridge`, but the runtime-backed pane path currently makes a nearly invisible `FallbackTerminalTextView` the interactive AppKit surface. In `RuntimeTerminalSurfaceContentHost`, the actual `GhosttyHostedSurfaceView` renders the terminal while the overlay text view receives first-responder focus, key events, paste commands, and mouse-down focus changes. `GhosttyHostedSurfaceView` itself only synchronizes layout and backing metrics.

This architecture is sufficient for simple printable input, but it bypasses the AppKit text-input machinery required for dead keys, compose/preedit, IME, and right-Option-sensitive layouts. It also prevents the visible runtime surface from naturally owning mouse selection, scroll, link hover, copy, paste, select-all, and clipboard callbacks. The result is a terminal that renders through Ghostty but does not yet behave like Ghostty's native macOS terminal surface.

The public libghostty C API already exposes the host integration points OpenMUX needs: key translation, key dispatch, preedit updates, IME geometry, binding actions, mouse events, selection reads, and clipboard callbacks. The design should use those APIs inside the bridge while preserving an OpenMUX-native boundary for the rest of the app.

## Goals / Non-Goals

**Goals:**
- Make runtime-backed terminal panes interactive through a production-grade AppKit adapter instead of the hidden fallback text overlay.
- Support macOS dead keys, IME/preedit, right/left modifier fidelity, Ghostty-compatible `macos-option-as-alt` behavior, and EU/ISO keyboard layouts as blocker-level terminal behavior.
- Route terminal-focused commands such as Copy, Paste, and Select All through terminal semantics rather than generic text-view behavior.
- Forward pointer, scroll, focus, and selection interactions to the runtime surface so terminal-native selection and hover behavior are preserved.
- Keep libghostty-specific types and calls localized to `OmuxTerminalBridge`.
- Preserve fallback terminal behavior as a compatibility path without letting fallback implementation details define runtime behavior.

**Non-Goals:**
- Implement general Ghostty action dispatch; that remains a separate change.
- Replace OpenMUX workspace, pane, or keymap architecture with Ghostty app-shell concepts.
- Copy Ghostty's macOS app-layer implementation; Ghostty may inform expected behavior and API usage only.
- Add browser-based UI, background daemons, or vendor-specific input services.
- Guarantee full automated coverage for every physical keyboard layout and IME in the first implementation; a manual verification matrix is acceptable where macOS automation is impractical.

## Decisions

### 1. Make the runtime Ghostty host view the interaction owner

`GhosttyHostedSurfaceView` should become the AppKit interaction adapter for runtime-backed panes. It should accept first responder, receive key, flag, command, mouse, scroll, and text-input events, and call private runtime methods on `CGhosttyRuntime` to reach the underlying `ghostty_surface_t`.

The runtime path should remove the full-size `FallbackTerminalTextView` overlay. The fallback text view remains for fallback panes only.

**Rationale:** The current overlay intercepts the exact interactions Ghostty needs to handle terminal behavior correctly. Making the visible runtime view interactive aligns rendering, focus, selection, mouse, IME, and clipboard behavior around one surface.

**Alternatives considered:**
- Keep the overlay and add more overrides. This would continue duplicating terminal interaction behavior and would still risk blocking runtime mouse/selection behavior.
- Make AppShell own runtime input. This would leak bridge concerns upward and make it harder to preserve the libghostty boundary.

### 2. Keep Ghostty-specific mechanics behind bridge-private methods

`GhosttyHostedSurfaceView` may live in `CGhosttyRuntime.swift`, but it should not expose Ghostty C types outside `OmuxTerminalBridge`. The view should call runtime-owned helpers for operations such as key dispatch, preedit updates, binding actions, clipboard completion, selection reads, mouse events, and focus changes.

**Rationale:** The app shell should continue to think in OpenMUX concepts: panes, focus, sessions, and hosted views. Ghostty enums, pointers, and payload structs remain an implementation detail of the bridge.

**Alternatives considered:**
- Expose `ghostty_surface_t` or C event structs to AppShell. This would violate the bridge boundary and make future terminal-engine changes harder.

### 3. Use AppKit text input for composition and IME

The runtime host view should implement `NSTextInputClient` and route `keyDown` through `interpretKeyEvents`. It should maintain marked-text state, distinguish preedit from committed text, call `ghostty_surface_preedit` for preedit updates, and use `ghostty_surface_ime_point` to place IME candidate UI near the terminal cursor.

Committed text from `insertText` should be sent once. Composition cancellation must clear preedit without emitting stray terminal input.

**Rationale:** Dead keys and IME are AppKit text-input behaviors, not simple `NSEvent.characters` cases. Treating composition as a first-class state is necessary for Nordic dead keys, compose-like flows, and non-Latin input.

**Alternatives considered:**
- Improve `DefaultKeyEventNormalizer` only. This may fix some direct key mappings but cannot correctly model marked text, candidate windows, or IME commit/cancel semantics.

### 4. Use Ghostty key translation and binding APIs for runtime panes

Runtime key handling should consult `ghostty_surface_key_translation_mods` before constructing text-bearing key events, preserve hidden AppKit event bits needed for dead keys, and call `ghostty_surface_key`. Runtime command routing should use `ghostty_surface_key_is_binding` and `ghostty_surface_binding_action` where appropriate.

OpenMUX may own the user-facing `macos-option-as-alt` configuration, but the behavior must remain Ghostty-compatible for `false`, `true`, `left`, `right`, and unset/default. The bridge should pass the effective setting to Ghostty and the host adapter should preserve original left/right Option identity, ask Ghostty for translation modifiers, use those translated modifiers only for AppKit text generation, and send the original modifier identity into the runtime key event. This ensures OpenMUX honors which Option side acts as Alt/Meta while AppKit continues to produce layout-correct text for whichever Option side remains text-producing.

Copy, Paste, and Select All should map to terminal binding actions for runtime panes:
- Copy: `copy_to_clipboard`
- Paste: `paste_from_clipboard`
- Select All: `select_all`

**Rationale:** Ghostty already owns terminal binding semantics. OpenMUX should adapt AppKit events into those semantics instead of injecting arbitrary text when the runtime can handle the terminal operation.

**Alternatives considered:**
- Continue using `ghostty_surface_text` for paste. This is simple but may bypass bracketed paste, clipboard confirmation, and terminal binding semantics.
- Invent divergent `macos-option-as-alt` semantics in OpenMUX. OpenMUX may expose and persist the setting, but the accepted values and behavior should stay compatible with Ghostty so users get the same `false`, `true`, `left`, and `right` meanings.

### 5. Add explicit clipboard callback handling

`CGhosttyRuntime` should replace stubbed clipboard callbacks with host implementations for standard clipboard read/write using `NSPasteboard`. Clipboard requests that require confirmation should surface through an OpenMUX-owned confirmation path before calling `ghostty_surface_complete_clipboard_request`.

Selection clipboard support should be explicit. For macOS v1, the default can remain unsupported unless a concrete runtime behavior requires it, but the unsupported behavior must be intentional and test-covered.

**Rationale:** Runtime paste/copy behavior is incomplete while `read_clipboard_cb` returns false and `write_clipboard_cb` is a no-op. A terminal cannot be production-ready on macOS without standard clipboard integration.

**Alternatives considered:**
- Keep host paste as direct `NSPasteboard` string injection only. This ignores runtime clipboard APIs and cannot support OSC 52 or terminal-owned copy behavior cleanly.

### 6. Forward pointer, selection, and scroll to the runtime surface

The runtime host view should forward mouse buttons, motion, drag, enter/exit, scroll, and pressure events to libghostty using the public mouse APIs. Click-to-focus must both focus the OpenMUX pane and deliver the relevant pointer event to the runtime surface.

The app shell should keep only pane focus ownership. Terminal selection ownership belongs to the terminal runtime for runtime-backed panes.

**Rationale:** The overlay likely blocks runtime-native selection and hover behavior today. Pointer and selection correctness are part of terminal interaction fidelity and directly affect copy behavior.

**Alternatives considered:**
- Keep selection in an overlay text view. This diverges from the rendered terminal content and cannot reliably match runtime buffer selection.

### 7. Add a standard AppKit command surface

OpenMUX should expose standard Edit-menu commands for Copy, Paste, and Select All, routed through the first responder. Runtime-backed terminal views and fallback terminal views should each implement the relevant responder actions.

**Rationale:** Reliable `Cmd+C`, `Cmd+V`, and `Cmd+A` behavior depends on normal AppKit command routing, not just local `keyDown` shortcuts.

**Alternatives considered:**
- Detect command keys only in `keyDown`. AppKit command routing can bypass or transform these events, and menu/responder integration is the platform-native solution.

## Risks / Trade-offs

- [Risk] AppKit text-input behavior is subtle and layout-dependent. → Mitigate by keeping the adapter narrow, modeling preedit explicitly, preserving Ghostty-compatible `macos-option-as-alt` semantics, and validating with US, Swedish/Nordic, EU/ISO, and at least one IME workflow.
- [Risk] Removing the overlay may regress focus behavior. → Mitigate by making pane focus handoff an explicit responsibility of the runtime host view and preserving `PaneID`-based focus callbacks.
- [Risk] Clipboard confirmation and OSC 52 behavior may require more UI than expected. → Mitigate by defining a minimal confirmation path and keeping policy in OpenMUX-owned types.
- [Risk] Fallback and runtime panes may diverge. → Mitigate by documenting fallback parity requirements and sharing OpenMUX-level command routing where possible.
- [Risk] Ghostty API assumptions may change. → Mitigate by localizing all C API usage in `OmuxTerminalBridge` and keeping OpenMUX specs expressed in engine-agnostic behavior.

## Migration Plan

1. Add runtime-host interaction responsibilities inside `OmuxTerminalBridge` while preserving existing fallback behavior.
2. Make `GhosttyHostedSurfaceView` the focus target for runtime-backed panes and remove the runtime overlay only after keyboard, command, and pointer paths are wired.
3. Add standard AppKit Edit commands and route them through first responder.
4. Replace runtime clipboard stubs with standard clipboard handling.
5. Add focused tests for bridge boundaries, side-specific Option semantics, Ghostty-compatible option-as-alt behavior, and AppKit command routing; keep manual verification for physical layout/IME cases that are difficult to automate.

Rollback is straightforward while this remains behind the runtime host path: restore the existing overlay focus target and disable the new runtime interaction adapter if a serious regression appears.

## Verification Strategy

Automated tests should validate the adapter contract without depending on the maintainer having every physical keyboard. Unit and integration tests should use synthetic AppKit events, injected modifier flags, and test doubles around Ghostty translation-modifier responses to verify:
- original left/right Option identity is preserved;
- translated modifiers are used only for text generation;
- original modifiers are sent to runtime key dispatch;
- `macos-option-as-alt` values `false`, `true`, `left`, `right`, and unset/default have Ghostty-compatible behavior even if OpenMUX owns the user-facing configuration;
- layout-produced text is whatever AppKit reports for the active or simulated layout, not a Swedish-specific hardcoded map.

Manual verification should supplement automated tests with a small physical-keyboard matrix. Swedish/Nordic ISO is a mandatory regression fixture because it motivated the change, but it is not the only supported layout. US and at least one additional EU layout should be included where contributors or CI hardware can provide them.

Recommended manual release matrix:
- US layout: direct punctuation, Command-C/V/A routing, and Option text when `macos-option-as-alt = false`.
- Swedish/Nordic ISO: dead keys `¨`, `^`, `~`; direct text `å`, `ä`, `ö`; Left Option text such as `@`, `[`, `]`; and Right Option Alt/Meta behavior when `macos-option-as-alt = right`.
- One additional EU layout when available: confirm OpenMUX preserves AppKit-reported Option text instead of hardcoded layout mappings.
- One IME workflow: preedit start/update, candidate-window placement, single commit, and cancellation without stray terminal text.

## Open Questions

- Should macOS selection clipboard remain unsupported for v1, or should it be mapped to a private pasteboard for compatibility with Ghostty's selection namespace?
- What confirmation UX should OpenMUX use for clipboard read/write requests, especially OSC 52?
- How much of dead-key and IME behavior can be automated reliably in CI versus documented as a manual release verification matrix?
- Should fallback panes use the same Edit-menu command routing as runtime panes even when their behavior is necessarily text-view based?
- Which additional physical EU layout should be part of the recurring manual release matrix alongside Swedish/Nordic and US?
