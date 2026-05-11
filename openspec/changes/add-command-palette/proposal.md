## Why

Developers need a fast keyboard-first way to move between workspaces and invoke available OpenMUX actions without leaving the terminal flow. A command palette gives OpenMUX a familiar, inspectable control surface while keeping the terminal as the primary workspace rather than adding browser-heavy or vendor-specific UI.

## Goals

- Add a command palette opened by `Cmd+P` for workspace search and switching.
- Add `Cmd+Shift+P` to open the same palette with `>` prefilled for command-mode search.
- Use a leading `>` prefix to search and trigger safe discoverable OpenMUX actions and safe-default `omux` CLI commands.
- Keep palette behavior keyboard-first, fast, and backed by explicit OpenMUX-native action/workspace/command contracts.
- Preserve keyboard correctness for macOS shortcuts, including ISO/EU layouts, dead keys, IME composition, and right-Option behavior.

## Non-goals

- Do not introduce a browser-based command UI or webview-first command surface.
- Do not make the palette an AI-first feature or a monolithic global launcher for unrelated workflows.
- Do not expose `libghostty` implementation types through palette APIs.
- Do not add long-running background indexing services for the initial palette.

## What Changes

- Introduce a command palette overlay in the macOS app shell.
- Bind `Cmd+P` to open the palette with an empty search field that lists currently open workspaces and switches to a selected non-current workspace.
- Bind `Cmd+Shift+P` to open the palette with `>` already entered, searching safe discoverable OpenMUX actions and safe-default `omux` CLI commands.
- Interpret user-entered `>` as an explicit command-mode prefix; removing the prefix returns the palette to workspace search mode.
- Provide searchable metadata for safe invokable actions, including shortcut labels when available, and supported safe-default `omux` CLI commands.
- Defer full CLI command invocation with argument prompting, path entry, target selection, quoting, and confirmation semantics to a separate future change.
- Ensure invocation routes through existing OpenMUX-native action and control-plane boundaries rather than coupling the palette to terminal engine internals.

## Capabilities

### New Capabilities

- `command-palette`: Covers palette presentation, search modes, keyboard shortcuts, result selection, and command/workspace invocation behavior.

### Modified Capabilities

- `keybinding-config`: Adds default bindings for `Cmd+P` and `Cmd+Shift+P` and defines how they participate in configurable keyboard handling.
- `terminal-action-dispatch`: Extends action discovery and invocation so palette results can trigger safe discoverable actions through the same dispatch path.
- `workspace-session-actions`: Adds palette-driven workspace search and switch behavior.
- `omux-control-plane`: Defines how supported `omux` CLI commands are discoverable and invokable from command-mode palette search.
- `appkit-terminal-input`: Ensures palette shortcuts are captured correctly without breaking terminal text input, IME composition, dead keys, or Option-key semantics.

## Impact

- Affects macOS app shell UI and focus handling for a modal palette overlay.
- Affects keybinding defaults and keyboard shortcut resolution for `Cmd+P` and `Cmd+Shift+P`.
- Affects action dispatch contracts for discoverable command metadata and invocation.
- Affects workspace/session switching contracts by adding palette search as another entry point.
- Affects `omux` CLI/control-plane command metadata so palette command mode can list and trigger supported commands.
- Does not require changes to the `libghostty` bridge boundary; terminal-engine specifics remain isolated behind existing OpenMUX-native abstractions.
