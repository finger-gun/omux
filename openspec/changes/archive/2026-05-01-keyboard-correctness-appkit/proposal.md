## Why

OpenMUX currently routes runtime terminal input through a thin AppKit proxy that fails on dead keys, composition, right-Option behavior, and command-driven clipboard interactions. This is a blocker for a terminal-first developer workspace, especially because international keyboard correctness is part of OpenMUX's product promise and the current bridge is replacing richer host behavior that production users expect.

## What Changes

- Introduce a production-grade AppKit terminal interaction layer for embedded Ghostty surfaces so keyboard input, composition, IME, and modifier handling behave correctly on macOS.
- Define explicit terminal interaction requirements for ISO/EU layouts, right-Option semantics, Ghostty `macos-option-as-alt` behavior, dead keys, compose/preedit flows, and command routing for terminal-focused panes.
- Add host-side clipboard and selection behavior requirements for terminal panes, including paste, copy, select-all, and runtime clipboard integration at the Ghostty bridge boundary.
- Clarify ownership of keyboard, pointer, selection, and clipboard behavior in the `OmuxTerminalBridge` so libghostty remains behind a narrow OpenMUX-native boundary.
- Preserve a performance-conscious, native AppKit design; this change must not introduce browser-heavy UI, background daemons, or monolithic terminal-side policy.

### Goals

- Make embedded terminal panes behave like a correct macOS terminal for real developer keyboards, not just US layouts.
- Restore confidence that OpenMUX can support EU/ISO layouts, side-specific Option behavior, Ghostty-compatible `macos-option-as-alt` settings, and dead-key composition as first-order product requirements.
- Specify a stable, explicit contract for terminal interaction behavior that can be tested and evolved without leaking libghostty types across the app.
- Keep terminal interaction native, inspectable, and compatible with future hooks, automation, and control-plane features.

### Non-goals

- Reworking general action dispatch; Ghostty action callbacks remain a separate change.
- Introducing browser-heavy architecture, vendor-specific services, or always-on background processes.
- Turning OpenMUX into a monolithic terminal shell that hardcodes every future workflow into the core.
- Copying Ghostty app-layer or GPL implementation code; any inspiration remains clean-room and behavioral only.

## Capabilities

### New Capabilities
- `appkit-terminal-input`: Defines how focused terminal panes handle key events, dead keys, IME/preedit, modifier fidelity, shortcut routing, and terminal interaction ownership on macOS.
- `terminal-clipboard-integration`: Defines copy, paste, select-all, and runtime clipboard behavior for embedded terminal panes, including host command routing and Ghostty bridge integration.
- `terminal-pointer-selection`: Defines mouse, scroll, pointer-position, focus handoff, and terminal selection behavior for embedded terminal panes.

### Modified Capabilities
- None.

## Impact

- Affected code is concentrated in `Sources/OmuxTerminalBridge/` and the AppKit window/pane hosting path in `Sources/OmuxAppShell/`.
- The `libghostty` bridge boundary will gain stricter requirements around input translation, preedit/IME handling, bindings, selection, and clipboard callbacks, but Ghostty-specific types must remain localized to the bridge.
- Terminal pane UX, keyboard correctness, pointer behavior, selection behavior, and clipboard behavior will change at the spec level for runtime-backed panes.
- Test coverage will need to expand beyond abstract key normalization to include AppKit interaction flows, layout-sensitive keyboard cases, pointer/selection behavior, and clipboard command routing.
