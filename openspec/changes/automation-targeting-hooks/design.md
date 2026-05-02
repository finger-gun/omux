## Context

OpenMUX has three pieces that are now close enough to compose: filesystem hooks, a JSON-RPC control plane, and shared workspace/session actions. The missing layer is reliable automation ergonomics. Today, a hook can observe an event, but it cannot easily discover targets, chain pane actions, write back to a terminal, or depend on `omux run` always submitting a command.

The current object model is intentionally OpenMUX-native:

```text
WorkspaceID
  -> TabID
      -> PaneStackID
          -> PaneID
              -> SessionID
```

Workspace and tab IDs identify containers. Pane and session IDs identify terminal endpoints. Automation should accept convenient container selectors, but internally every terminal mutation must resolve to one live pane/session pair before sending text, commands, focus, or split actions.

## Goals / Non-Goals

**Goals:**

- Make control-plane commands usable while `omux events` is running.
- Define one target-resolution model for CLI, JSON-RPC, hooks, and shared actions.
- Separate command execution from raw text insertion.
- Return structured action results that scripts can chain without scraping human output.
- Add command-failure hooks and richer command payloads without exposing Ghostty internals.
- Keep all automation local-first and process-based.

**Non-Goals:**

- No embedded TypeScript, Deno, Lua, browser, or WASM runtime in this change.
- No AI-specific core API. AI analysis is just an external hook script using public commands.
- No hook stdout command protocol. Hooks mutate OpenMUX by calling `omux` or JSON-RPC explicitly.
- No full terminal transcript database. This change only needs bounded output context or explicit unavailable state.

## Decisions

### Use explicit target selectors instead of overloading positional IDs

Automation commands will accept a shared target selector:

```text
--session <session-id>    exact terminal session
--pane <pane-id>          active local tab/session in that pane
--tab <tab-id>            focused terminal inside that workspace tab
--workspace <id>          focused terminal inside that workspace
--focused                 globally focused terminal
```

`--session` is the most precise target. `--pane`, `--tab`, `--workspace`, and `--focused` are convenience selectors that resolve to a session at execution time. This avoids ambiguous "workspace ID passed to run" behavior while preserving useful hook ergonomics.

Alternative considered: make every command accept any ID and infer its type. That is convenient but error-prone, especially because users can paste IDs from hooks and get surprising behavior if an ID type changes or collides. Explicit selectors are clearer and easier to document.

### Keep `runCommand` and `sendText` separate

`runCommand` means "send this command and submit it". `sendText` means "insert exactly this text into the target terminal input stream". `sendText` does not append Return, and `runCommand` owns the backend-specific Return behavior.

This distinction matters for hooks:

```text
command-failed hook
  -> call external analyzer
  -> omux send-text --session "$OMUX_SESSION_ID" "analysis..."
```

The hook can write a note without accidentally executing it.

### Resolve targets in app-shell action code, not the CLI

The CLI should parse selectors and send a typed target request. The app shell owns workspace topology and should resolve selectors against current live state. This keeps the CLI thin and ensures UI actions, hooks, and JSON-RPC all share the same behavior.

### Make event streams non-blocking at the server boundary

Long-lived event connections must not occupy the only accept/request loop. The transport can solve this with per-connection workers, tasks, or another concurrency primitive, but the requirement is behavioral: one `omux events` subscriber must not prevent independent request/response commands from being accepted and completed.

### Preserve the libghostty bridge boundary for command submission

The fix for `omux run` must live behind OpenMUX terminal bridge APIs. App-shell and CLI code should continue to talk in terms of `run(command:)` and `send(text:)`; they should not learn Ghostty key event structs or raw C APIs.

For runtime-backed panes, command submission likely requires sending command text through the text path and Return through the runtime's key-input path rather than encoding carriage return as text. The fallback runtime can keep its existing behavior if it already submits commands correctly.

Keyboard correctness is part of this boundary. `sendText` is automation text insertion, not a replacement for physical keyboard handling. It must not reinterpret Option/Alt, dead keys, compose keys, or IME input. `runCommand` should synthesize only the submit action needed for command execution.

### Treat output context as bounded and optional

Command-failure automation benefits from output context, but a full transcript store is out of scope. Command-finished and command-failed payloads should include either:

- a bounded output tail when the app has one, or
- an output reference if a later implementation stores one, or
- an explicit unavailable/null value.

Hooks must never receive Ghostty-owned payload structs. Any output context is OpenMUX-owned text or an OpenMUX-owned reference.

## Risks / Trade-offs

- [Risk] Target selectors could become confusing if command docs are inconsistent. -> Mitigation: document the shared selector model once and reuse it across `run`, `send-text`, `split`, `focus`, and discovery commands.
- [Risk] Concurrent control-plane handling could introduce shared-state races. -> Mitigation: keep app-state mutation on the app/main actor or existing serialized action boundary; only unblock socket connection handling.
- [Risk] `sendText` can be used to inject input into terminals. -> Mitigation: keep the control plane local, use exact target selectors, and document that hooks run with the user's local privileges.
- [Risk] Command output capture can grow memory usage. -> Mitigation: bound captured tails and make unavailable output explicit rather than buffering unbounded transcripts.
- [Risk] Synthesizing Return through Ghostty may accidentally bypass input semantics. -> Mitigation: keep the behavior inside the terminal bridge and test command submission separately from raw text insertion.
