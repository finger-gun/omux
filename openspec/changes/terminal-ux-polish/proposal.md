## Why

OpenMUX currently misses several native terminal interaction expectations: long theme lists can render outside small terminals, dropped files are not pasted into terminal input, Command-arrow navigation can be swallowed, and double-clicking the unified titlebar does not zoom the window. These regressions make the terminal feel less native and less dependable for daily developer workflows.

## Goals

- Keep terminal-focused interactions visible, reachable, and predictable in small panes and native macOS windows.
- Restore common terminal emulator behaviors without expanding the libghostty boundary.
- Preserve keyboard correctness for command shortcuts, Control chords, Option/right-Option layout behavior, dead keys, and IME input.
- Add regression coverage for the behavior that can be validated automatically.

## Non-goals

- Introduce browser or webview-based UI for picker or terminal interactions.
- Add a new background service, plugin API, or vendor-specific workflow.
- Implement inline image protocols or binary image upload on drag/drop; the first supported behavior is safe text insertion of dropped file paths.
- Change global macOS shortcut semantics beyond the narrow terminal navigation exception.

## What Changes

- Constrain the interactive `omux theme` picker to the visible terminal height and keep the highlighted theme within a scrolling viewport.
- Add terminal file/image drag-and-drop handling that pastes dropped file paths as shell-safe text through the existing terminal input path.
- Route Command-Left and Command-Right in focused terminal panes to beginning/end-of-line terminal input behavior while preserving existing app shortcuts.
- Restore native double-click titlebar zoom/maximize behavior for the transparent full-size-content workspace window.
- Add automated regression tests for picker viewporting, terminal drag/drop path formatting where possible, command-arrow routing, and window titlebar configuration.

## Capabilities

### New Capabilities

- `theme-cli`: CLI theme selection behavior, including interactive picker viewporting and scriptable fallbacks.

### Modified Capabilities

- `appkit-terminal-input`: Terminal-focused AppKit input behavior for command-arrow navigation and dropped file path insertion.
- `macos-app-shell`: Native window chrome behavior for transparent titlebar double-click zoom.

## Impact

- Affected code:
  - `Sources/OmuxCLI/OmuxCLI.swift`
  - `Sources/OmuxTerminalBridge/RuntimeTerminalHostView.swift`
  - `Sources/OmuxTerminalBridge/HostedTerminalPaneView.swift`
  - `Sources/OmuxTerminalBridge/GhosttyTerminalBridge.swift`
  - `Sources/OmuxAppShell/WorkspaceWindowController.swift`
- Affected tests:
  - `Tests/OmuxCLITests`
  - `Tests/OmuxTerminalBridgeTests`
  - `Tests/OmuxAppShellTests`
- Keyboard/input impact:
  - Command-Left and Command-Right receive explicit terminal navigation handling.
  - Other Command shortcuts remain responder/menu shortcuts.
  - Existing Option/right-Option, dead-key, and IME behavior must remain unchanged.
- Bridge impact:
  - libghostty types remain inside `OmuxTerminalBridge`.
  - File drops and command-arrow fallback text use existing OpenMUX-native bridge paths instead of exposing runtime internals to AppShell.
