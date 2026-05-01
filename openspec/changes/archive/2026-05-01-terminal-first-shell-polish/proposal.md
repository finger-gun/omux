## Why

OpenMUX has the right foundation, but the shell still spends too much space and visual weight on chrome instead of terminals. The current top bar adds little value, pane regions are nested inside multiple rounded bordered containers, the native titlebar still reads as a separate surface, and workspace navigation is slower than it should be for keyboard-first use.

## Goals

- Make the shell feel more terminal-first by removing low-value chrome and giving more space to panes.
- Tighten workspace navigation with direct keyboard shortcuts and faster workspace switching.
- Keep the shell AppKit-first and OpenMUX-owned rather than letting terminal-engine assumptions shape the UI.
- Improve speed of use without adding background services, browser-heavy surfaces, or vendor-specific workflow opinions.

## Non-goals

- Reworking terminal rendering or libghostty integration.
- Building a generalized command palette or a full keybinding system.
- Changing core workspace/session semantics beyond what is needed for faster navigation and a cleaner shell.
- Introducing browser-like layout chrome, webview surfaces, or monolithic UI layers.

## What Changes

- Remove the current top header bar and reclaim its vertical space for pane content.
- Reduce shell chrome by flattening or removing rounded bordered canvas and pane-card containers, keeping only the minimum shell structure needed for navigation and pane context.
- Blend the native macOS titlebar more closely with the shell background so the window reads as one terminal-first surface instead of stacked UI bands.
- Add a collapsible workspace sidebar/column so users can hide navigation chrome when they want maximum pane space.
- Add direct workspace navigation shortcuts: jump to workspace `1` through `9`, and jump back to the previous active workspace with `Cmd+0`.
- Adopt shortcut defaults that better match keyboard-driven workspace use, including `Cmd+D` for split right, `Cmd+Shift+D` for split down, `Cmd+B` for toggling the workspace column, and preserving `Cmd+N` for new workspace.
- Keep shell shortcuts routed through OpenMUX-owned input/menu handling so terminal input correctness and shell commands remain separate concerns.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `macos-app-shell`: Requirements change to support a lower-chrome terminal-first shell, a collapsible workspace column, and titlebar/background integration that keeps shell ownership in AppKit.
- `workspace-session-actions`: Requirements change to support direct workspace switching, previous-workspace navigation, and split actions that are reachable through faster shell shortcuts.
- `input-pipeline`: Requirements change to ensure shell shortcuts for split/navigation/toggle behaviors coexist with keyboard correctness for ISO/EU layouts, Option behavior, and terminal input routing.

## Impact

- **Code**:
  - `Sources/OmuxAppShell/WorkspaceWindowController.swift` for top-bar removal, canvas/pane chrome reduction, sidebar collapse behavior, and titlebar/window styling.
  - `Sources/OmuxAppShell/OpenMUXAppDelegate.swift` and related shell command wiring for shortcut/menu changes.
  - `Sources/OmuxAppShell/WorkspaceController.swift` for workspace switching helpers and previous-active workspace behavior.
  - Potential small updates to shared workspace models or summaries if numeric navigation/history needs explicit state.
- **APIs and behavior**:
  - App-shell keyboard shortcuts and visible shell structure change.
  - Workspace navigation becomes more direct and keyboard-oriented.
- **Architecture**:
  - Keeps the libghostty bridge untouched and preserves AppKit ownership of shell behavior.
  - Keeps shortcut routing inside OpenMUX-owned shell/input seams instead of leaking terminal-engine assumptions upward.
- **Keyboard/input correctness**:
  - Shortcut additions must be evaluated against ISO/EU layouts, Option handling, and terminal focus so shell shortcuts do not break text input expectations.
- **Manifest alignment**:
  - *Terminal first*: more space and emphasis goes to panes instead of decorative shell chrome.
  - *Performance-conscious*: simplification reduces UI weight rather than adding more surface area.
  - *Open by design* and *hackable*: navigation behavior stays explicit and shell-owned, making later customization easier.
