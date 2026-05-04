## Why

OpenMUX currently exposes terminal title changes and command completion, but it does not expose explicit input that OpenMUX deliberately sends into a terminal through shared actions such as `omux run` and `send-text`. A terminal-first, hackable workspace should let local automation observe those deliberate sends without streaming every native keystroke or pretending input is a fully parsed shell command.

## Goals

- Emit a first-class `terminal.inputSent` event when OpenMUX successfully delivers explicit action-scoped input to a live terminal runtime.
- Preserve the distinction between terminal input and shell commands: action-scoped input may be command text from `omux run` or arbitrary text from `send-text`, but it is not a generic shell command parser.
- Make the event useful to hooks and event subscribers through stable workspace/tab/pane/session context and typed input payload fields.
- Keep input observation lightweight, without parsing shell prompts, titles, scrollback, or native per-keystroke AppKit input.

## Non-goals

- Do not infer shell commands from `terminal.titleChanged`, prompt rendering, or unbounded scrollback.
- Do not stream native pane typing as per-character or per-key input events.
- Do not implement command approval/interception before execution in this change.
- Do not build a shadow shell-editing buffer that attempts to understand history navigation, multiline commands, shell quoting, or IME composition as commands.
- Do not introduce browser-heavy, vendor-specific, or in-process plugin machinery.

## What Changes

- Add an OpenMUX-native `terminal.inputSent` event for explicit terminal input actions successfully delivered to a live runtime surface.
- Publish input-sent events on the `omux events` stream with workspace, tab, pane, session, text/key metadata, modifier metadata, route metadata, and source.
- Invoke a `terminal-input-sent` hook with the same OpenMUX-native input context.
- Keep `terminal.titleChanged` as presentation metadata only; it MUST NOT be treated as authoritative command text.
- Preserve all libghostty-specific input details behind `OmuxTerminalBridge` and avoid emitting raw UI key/text fragments.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `terminal-action-dispatch`: Add explicit action-scoped input-sent terminal event semantics and prohibit deriving command text from title changes.
- `control-plane-action-events`: Stream `terminal.inputSent` through the existing local event subscription contract.
- `hooks-foundation`: Add the `terminal-input-sent` hook and define its typed payload contract.
- `workspace-session-actions`: Ensure shared run-command and send-text paths emit input-sent lifecycle signals after successful delivery, while native typed terminal input remains unstreamed.

## Impact

- Affected code includes `OmuxTerminalBridge` input forwarding, `OmuxControlPlane` event naming, `OmuxAppShell` terminal action coordination, `OmuxHooks` invocation wiring, docs, and tests.
- The local JSON-RPC event stream gains a new event name but remains backward compatible for existing subscribers.
- Hook discovery gains a new hook name but keeps the existing external executable model.
- Keyboard/input correctness remains protected: OpenMUX does not stream or parse dead keys, Option/Alt behavior, IME composition, shell editing, or Return into authoritative shell commands.
- The libghostty bridge boundary remains narrow: raw Ghostty input structs and AppKit event objects must not escape into app-shell, hooks, CLI, or control-plane APIs.
