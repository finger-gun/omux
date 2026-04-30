## 1. Runtime interaction ownership

- [ ] 1.1 Refactor runtime-backed panes so `GhosttyHostedSurfaceView` is the runtime focus target instead of an overlaid `FallbackTerminalTextView`.
- [ ] 1.2 Keep `FallbackTerminalTextView` limited to fallback panes and preserve existing fallback session behavior.
- [ ] 1.3 Add bridge-local focus handoff so clicking a runtime-backed pane focuses the OpenMUX pane without swallowing the terminal event.
- [ ] 1.4 Add tests proving runtime-backed panes do not install the fallback text-view overlay as their input owner.

## 2. Runtime keyboard and text-input adapter

- [ ] 2.1 Make `GhosttyHostedSurfaceView` accept first responder and handle key down, key up, and flags-changed events for runtime-backed panes.
- [ ] 2.2 Implement side-specific modifier extraction from AppKit events for Shift, Control, Option, and Command without leaking Ghostty types outside `OmuxTerminalBridge`.
- [ ] 2.3 Implement `NSTextInputClient` state for marked text, selected range, preedit updates, committed text, cancellation, and IME candidate geometry.
- [ ] 2.4 Wire runtime text input to Ghostty bridge APIs for key dispatch, committed text, preedit, and IME cursor geometry.
- [ ] 2.5 Add tests for dead-key/preedit start, commit-once behavior, and composition cancellation without stray terminal input.

## 3. Ghostty-compatible option-as-alt and layout-neutral tests

- [ ] 3.1 Add or wire OpenMUX-owned `macos-option-as-alt` configuration so accepted values `false`, `true`, `left`, `right`, and unset/default map to Ghostty-compatible runtime behavior.
- [ ] 3.2 Ensure translated modifiers are used only for AppKit text generation while original left/right Option identity is sent to runtime key dispatch.
- [ ] 3.3 Add automated tests for `macos-option-as-alt = false`, `true`, `left`, `right`, and unset/default using test doubles or synthetic translation responses.
- [ ] 3.4 Add automated regression tests proving layout-produced Option text is injected from AppKit/test fixtures and not hardcoded for Swedish, German, US, or any other layout.
- [ ] 3.5 Add a Swedish/Nordic ISO regression fixture for `macos-option-as-alt = right` covering Left Option text input and Right Option Alt/Meta behavior.

## 4. AppKit command and clipboard integration

- [ ] 4.1 Add standard AppKit Edit-menu routing for Copy, Paste, and Select All through the first responder.
- [ ] 4.2 Implement runtime responder actions that map Copy, Paste, and Select All to terminal runtime binding actions.
- [ ] 4.3 Replace stubbed runtime clipboard callbacks with standard macOS pasteboard read/write handling for runtime-backed panes.
- [ ] 4.4 Define and implement explicit behavior for unsupported selection-clipboard requests on macOS.
- [ ] 4.5 Add tests for Command-C, Command-V, and Command-A routing in runtime-backed and fallback terminal panes.
- [ ] 4.6 Add tests for runtime clipboard read/write callbacks and unsupported selection-clipboard behavior.

## 5. Pointer, selection, and scroll integration

- [ ] 5.1 Forward runtime pointer button, movement, drag, enter, exit, scroll, and pressure events to the terminal bridge.
- [ ] 5.2 Translate AppKit pointer coordinates into runtime terminal viewport coordinates.
- [ ] 5.3 Ensure runtime terminal selection owns runtime-backed pane selection state.
- [ ] 5.4 Ensure Copy uses runtime terminal selection for runtime-backed panes rather than overlay or AppShell text selection.
- [ ] 5.5 Add tests for click-to-focus preserving the click event, scroll forwarding, runtime-relative coordinates, and selection ownership.

## 6. Verification and documentation

- [ ] 6.1 Document the manual keyboard verification matrix for US, Swedish/Nordic ISO, at least one additional EU layout when available, and at least one IME workflow.
- [ ] 6.2 Document that OpenMUX honors Ghostty-compatible `macos-option-as-alt` semantics and does not hardcode layout-specific Option mappings.
- [ ] 6.3 Run the existing Swift test suite and the new focused input, clipboard, and pointer tests.
- [ ] 6.4 Manually verify Swedish/Nordic ISO dead keys (`¨`, `^`, `~`), direct text (`å`, `ä`, `ö`), Option text input, and Right Option Alt/Meta behavior.
