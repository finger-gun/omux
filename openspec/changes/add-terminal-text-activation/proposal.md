## Why

Terminal output often contains useful local paths such as `README.md`, logs, images, and generated artifacts. OpenMUX should let users intentionally activate those text tokens from a terminal pane and let plugins handle them, without making normal terminal clicks less reliable.

## Goals

- Add an OpenMUX-native terminal text activation event for modifier-click gestures on terminal text.
- Preserve normal terminal mouse behavior for plain clicks, selection, TUIs, and terminal mouse reporting.
- Let plugins and hooks observe activated text with pane/session/workspace context, current working directory, modifiers, and a resolved local path when possible.
- Use the bundled Markdown preview plugin as the first activation consumer for readable local `*.md` and `*.markdown` files when enabled.
- Keep terminal hit-testing and runtime details behind `OmuxTerminalBridge` using OpenMUX-native event payloads.

## Non-goals

- Do not make plain clicks open files by default.
- Do not add a general browser or file manager to OpenMUX core.
- Do not require a plugin daemon or in-process third-party plugin runtime.
- Do not claim exact token hit-testing across all terminal rendering edge cases in the first version.
- Do not change terminal keyboard behavior, IME handling, or libghostty input encoding.

## What Changes

- Add terminal text activation types and event payloads for intentional modified pointer clicks.
- Add best-effort hit-testing from pointer location to a token in visible terminal text.
- Emit a hook/control-plane-style event for activated terminal text.
- Add a Markdown preview activation path that opens readable local Markdown files in an extension pane when the plugin is enabled.
- Document the activation gesture and plugin/hook payload shape.
- Add regression coverage that normal clicks still reach the terminal and modifier-clicking Markdown text opens preview.

## Capabilities

### New Capabilities

- `terminal-text-activation`: Covers modifier-click activation of terminal text tokens, emitted events, plugin dispatch, and Markdown preview handling.

### Modified Capabilities

- `terminal-pointer-selection`: Terminal pointer behavior gains a modified-click activation path while preserving normal pointer delivery and selection behavior.
- `hooks-foundation`: Hooks gain an input-category terminal text activation event payload that user scripts/plugins can observe.

## Impact

- **Terminal bridge:** Adds OpenMUX-native activation hit-testing and callback types without exposing Ghostty structs outside the bridge boundary.
- **App shell:** Handles activation events, emits hooks, resolves plugin enablement, and invokes Markdown preview pane creation/update.
- **Markdown preview plugin:** Reuses existing renderer and extension-pane lifecycle for activated Markdown paths.
- **Configuration:** First version uses a fixed macOS-style activation gesture, Command-click, with Shift-click as an optional alias if it does not conflict with terminal behavior.
- **Keyboard/input:** No terminal keyboard behavior changes; plain pointer events continue to flow to the runtime.
