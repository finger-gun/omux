## 1. Event Contract

- [x] 1.1 Add `terminal.inputSent` to the OpenMUX-native control-plane terminal event names without changing existing event names.
- [x] 1.2 Define a shared input-sent payload shape with `text`, `key`, `keyCode`, `modifiers`, `route`, and `source`, using null values where data is not available.
- [x] 1.3 Keep `terminal.titleChanged` as presentation metadata and avoid using it as authoritative command text.

## 2. Bridge Input Integration

- [x] 2.1 Emit `terminal.inputSent` only after explicit OpenMUX input actions successfully deliver text to a live runtime surface.
- [x] 2.2 Do not emit `terminal.inputSent` from native typed text or terminal key forwarding paths.
- [x] 2.3 Preserve the existing `command.started` action event and `command-started` hook behavior for run-command action parity.
- [x] 2.4 Ensure failed target resolution or bridge delivery failure does not emit `terminal.inputSent`.

## 3. Hook Integration

- [x] 3.1 Add `terminal-input-sent` hook emission with input category, workspace/tab/pane/session context, and the shared input-sent payload.
- [x] 3.2 Keep input-sent hooks observational so handler failures do not cancel or undo forwarded terminal input.
- [x] 3.3 Ensure hook payloads remain OpenMUX-native and do not expose Ghostty action tags, AppKit input events, or bridge internals.

## 4. Runtime and Input Boundary

- [x] 4.1 Confirm terminal action dispatch does not fabricate command text from title changes, prompt rendering, or scrollback.
- [x] 4.2 Preserve keyboard/input behavior by avoiding any shadow command-line parser for typed text, dead keys, Option/Alt input, paste, shell editing, or IME composition.
- [x] 4.3 Translate action-scoped forwarded input to OpenMUX-native input-sent data while keeping raw terminal-engine types inside `OmuxTerminalBridge`.

## 5. Documentation and Validation

- [x] 5.1 Update user-facing hook/event documentation to describe action-scoped `terminal.inputSent`, `terminal-input-sent`, payload fields, source semantics, no per-character native typing stream, and the title-change non-guarantee.
- [x] 5.2 Add control-plane/event tests for `terminal.inputSent` payload shape and event-stream publication.
- [x] 5.3 Add app-shell tests for successful run-command input-sent emission and no emission on failed input delivery.
- [x] 5.4 Add hook tests for `terminal-input-sent` invocation and hook failure isolation.
- [x] 5.5 Add regression coverage confirming title changes do not populate authoritative input-sent events.
- [x] 5.6 Add regression coverage confirming native typed input does not publish per-character `terminal.inputSent` events.
- [x] 5.7 Run relevant Swift test suites and `openspec validate add-terminal-command-sent-event --strict`.
