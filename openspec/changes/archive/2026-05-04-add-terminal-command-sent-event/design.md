## Context

OpenMUX already owns shared terminal actions such as `omux run` and `send-text`, and those paths deliberately send input into a targeted pane. Native AppKit text input, committed text, accumulated key text, and normalized key events also pass through `OmuxTerminalBridge`, but those observations are per-key or per-fragment terminal input rather than reliable shell command records.

The previous command-sent framing was too strong for manually typed commands. A user typing `ls` creates text/key input and later shell-integration events such as title changes or command completion, but OpenMUX does not receive one authoritative "the user submitted command ls" record from Ghostty. This design therefore keeps an input-sent event for deliberate OpenMUX input actions and intentionally avoids a native per-character input stream.

## Goals / Non-Goals

**Goals:**

- Add a stable OpenMUX-native `terminal.inputSent` event and `terminal-input-sent` hook.
- Emit the event only after OpenMUX successfully delivers explicit action-scoped input to the live runtime.
- Include enough context for automation: workspace ID, tab ID, pane ID, session ID, text when available, key/keyCode when available, modifiers, route, and source.
- Preserve the bridge boundary and keep raw Ghostty/AppKit input objects out of app-shell, hook, control-plane, and CLI contracts.
- Protect keyboard correctness by avoiding shell command parsing.

**Non-Goals:**

- Blocking or approving terminal input before it reaches Ghostty.
- Treating input fragments as parsed shell commands.
- Streaming native typed input, committed AppKit text, or per-key terminal input as default events.
- Treating `terminal.titleChanged` as authoritative command text.
- Adding a background shell monitor, browser/webview layer, embedded plugin runtime, or vendor-specific control service.

## Decisions

### Decision: emit input events from explicit OpenMUX input actions

`terminal.inputSent` is emitted from app-shell action paths that intentionally send input to a pane, currently `omux run`/run-command and `send-text`. The event is emitted only after the action successfully delivers the input to the runtime.

Alternative considered: emit from every bridge text/key forwarding path. This was rejected because native pane typing would create a noisy and sensitive per-character stream while still failing to provide authoritative shell command text.

### Decision: keep input payloads OpenMUX-native and fragment-oriented

Payloads carry OpenMUX-native fields: `text`, `key`, `keyCode`, `modifiers`, `route`, and `source`. Action-scoped text sends normally populate `text` and `source`; key fields remain available for future explicit key-sending actions. The event does not expose raw `NSEvent`, `ghostty_input_key_s`, or other terminal-engine structs.

Alternative considered: expose raw AppKit or Ghostty input objects. This was rejected because those objects are unstable implementation details and would violate the bridge boundary.

### Decision: no command reconstruction

OpenMUX should not accumulate typed text into a shell command buffer. Shell editing, history recall, multiline commands, bracketed paste, control/meta chords, Option text, dead keys, and IME composition make generic reconstruction unreliable.

Alternative considered: buffer printable text until Return and emit it as a command. This was rejected because it would produce false positives and regress keyboard correctness.

### Decision: hooks remain observational

`terminal-input-sent` is a normal external hook invocation with structured JSON on stdin. Hook handlers can react by calling public `omux` commands or JSON-RPC operations, but hook stdout does not become an implicit command protocol and hook failure does not block input already forwarded to the terminal.

Alternative considered: make the hook a synchronous input interceptor. This was rejected because blocking input policy needs separate latency, trust, and failure semantics.

## Risks / Trade-offs

- Input payloads may contain sensitive terminal input -> document that subscribers/hooks should opt in carefully and treat payloads as local-sensitive data.
- Action-scoped input is not a shell command parser -> use explicit naming and docs so automation does not assume manual command semantics.
- Native typing, paste, and runtime-owned input paths do not emit this event -> the event describes explicit OpenMUX input actions, not every internal runtime mutation.
- Run-command can produce both `terminal.inputSent` and `command.started` -> keep the event names and semantics distinct.

## Migration Plan

Existing events and hooks remain valid. The new event and hook are additive. No subscriber migration is required.

## Open Questions

- Whether a future change should add shell integration or a Ghostty export for authoritative manually typed command text.
- Whether blocking input policy should be a separate pre-input hook, a control-plane rule set, or a plugin contract.
