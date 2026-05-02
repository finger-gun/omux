## Why

OpenMUX currently takes too much responsibility for runtime-backed terminal input before events reach Ghostty, which can swallow terminal-owned chords such as `Cmd+Backspace` and `Option+Backspace` and risks diverging from Ghostty's mature macOS keyboard behavior. For a terminal-first developer workspace, input fidelity across macOS keyboards, IME flows, text selection, and terminal editing shortcuts is core product behavior rather than polish.

## Goals

- Narrow OpenMUX input ownership to pane focus, explicit OpenMUX shortcuts, native menu entry points, and observability.
- Let Ghostty own terminal input semantics for runtime-backed panes, including modified Backspace, Option/Alt behavior, key encoding, mouse selection, and terminal-owned editing/navigation behavior.
- Align OpenMUX's runtime AppKit adapter with the behavioral shape of Ghostty's own macOS adapter without copying implementation code or adopting Ghostty app-shell ownership.
- Preserve international keyboard correctness for ISO/EU layouts, side-specific Option behavior, dead keys, compose flows, and IME/preedit workflows.
- Keep the libghostty boundary narrow: direct Ghostty APIs remain confined to `OmuxTerminalBridge`.

## Non-goals

- Do not copy Ghostty macOS app source code into OpenMUX.
- Do not hand workspace, window, tab, split, config UI, update, or app-shell ownership to Ghostty.
- Do not add browser, webview, background-service, or vendor-hosted input infrastructure.
- Do not hardcode layout-specific key maps or synthesize shell-editing shortcuts such as `Option+Backspace -> Ctrl+W` in OpenMUX.
- Do not change CLI, hooks, or control-plane contracts except to preserve existing observability.

## What Changes

- Replace broad Command-modifier shortcut classification with an explicit OpenMUX shortcut allowlist for runtime-backed terminal panes.
- Ensure unclaimed keyboard input, including modified Backspace and non-OpenMUX Command chords, reaches the Ghostty runtime input path.
- Add AppKit text-command handling so commands produced by `interpretKeyEvents` are not silently swallowed when they should be terminal-owned.
- Expose runtime-owned Ghostty selection through the bridge for AppKit text-input queries where available, while keeping Ghostty as the source of truth.
- Improve tests around `Cmd+Backspace`, `Option+Backspace`, terminal-owned Command chords, IME/preedit preservation, and selection visibility.
- Update specs and development notes to describe the new ownership rule: OpenMUX is the input gate and adapter; Ghostty owns terminal semantics.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `input-pipeline`: Narrow the normalized-input responsibility from universal terminal dispatch to explicit shortcut classification and observation.
- `appkit-terminal-input`: Align runtime-backed terminal input with Ghostty-owned semantics and prevent unclaimed AppKit text commands from being swallowed.
- `terminal-pointer-selection`: Surface Ghostty-owned selection state to AppKit where available while preserving runtime ownership of selection.
- `terminal-bridge`: Extend the bridge with OpenMUX-native selection-reading support without leaking Ghostty types outside `OmuxTerminalBridge`.

## Impact

- Affected code and tests:
  - `Sources/OmuxCore/InputModel.swift`
  - `Sources/OmuxTerminalBridge/RuntimeTerminalHostView.swift`
  - `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift`
  - `Sources/OmuxTerminalBridge/GhosttyTerminalBridge.swift`
  - `Tests/OmuxCoreTests`
  - `Tests/OmuxTerminalBridgeTests`
  - input-related OpenSpec specs and development docs
- Keyboard/input correctness is directly affected and must be validated against Command/Option Backspace, ISO/EU Option text, side-specific modifiers, dead keys, and IME workflows.
- The change uses Ghostty's macOS app as behavioral and architectural inspiration only. OpenMUX remains AppKit-first, terminal-first, and OpenMUX-owned at the shell/workspace level.
