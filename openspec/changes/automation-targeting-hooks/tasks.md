## 1. Control-plane transport and contracts

- [x] 1.1 Rework local control-plane connection handling so long-lived event stream clients cannot block new request/response clients.
- [x] 1.2 Add focused tests proving `omux events` or an equivalent stream client can remain connected while independent commands complete.
- [x] 1.3 Add shared JSON-RPC target selector types for session, pane, tab, workspace, and focused-terminal targeting.
- [x] 1.4 Add structured action result types that carry targeted, focused, or created workspace/tab/pane-stack/pane/session IDs.

## 2. Target resolution and topology discovery

- [x] 2.1 Implement app-shell target resolution from selector types to a live workspace/tab/pane/session context.
- [x] 2.2 Add live topology responses that expose workspace, tab, pane stack, pane, session, and focused IDs for automation.
- [x] 2.3 Add CLI discovery commands or options, such as `omux sessions`, `omux panes`, and/or `omux list --full`, backed by the topology response.
- [x] 2.4 Add tests for valid and invalid selector resolution, including explicit failures for unresolved targets.

## 3. Terminal input actions

- [x] 3.1 Add a control-plane `session.sendText` or equivalent raw text-input method that resolves the shared target selector.
- [x] 3.2 Add `omux send-text` with the shared target selector flags and no implicit Return/Enter submission.
- [x] 3.3 Extend `omux run` to support selector flags while preserving `omux run <session-id> <command>` compatibility.
- [x] 3.4 Fix runtime-backed `runCommand` submission so commands execute without requiring the user to press Return manually.
- [x] 3.5 Add terminal bridge tests or app-shell integration tests that distinguish command execution from raw text insertion.

## 4. Scriptable workspace actions

- [x] 4.1 Ensure split, focus, run-command, and send-text use the shared target-resolution path.
- [x] 4.2 Enrich split and focus responses with created/focused IDs needed for hook script chaining.
- [x] 4.3 Add CLI output handling that preserves machine-readable JSON for automation while keeping human-readable output usable.
- [x] 4.4 Add tests for a chained workspace bootstrap flow: open workspace, split panes, focus target, and run a command in the selected pane.

## 5. Command hooks and output context

- [x] 5.1 Track OpenMUX-owned command context for commands sent through run-command, including command text and target IDs.
- [x] 5.2 Enrich command-started and terminal-command-finished payloads with command text, cwd when available, duration, exit code, and explicit output-context state.
- [x] 5.3 Add bounded output tail or output-reference support where available without introducing unbounded transcript buffering.
- [x] 5.4 Emit `command-failed` for nonzero command completions with the enriched command context.
- [x] 5.5 Add hook tests for successful command completion, nonzero command failure, and unavailable output context.

## 6. Documentation and validation

- [x] 6.1 Update `docs/hooks.md` with the new hook payloads, `command-failed`, target selector rules, and send-text behavior.
- [x] 6.2 Add a documented workspace bootstrap hook example that creates a split layout and runs `pnpm dev` in a selected pane.
- [x] 6.3 Add a documented command-failure analysis hook example that sends output context to an external analyzer and writes the result back through `omux send-text`.
- [x] 6.4 Update CLI/help documentation for selector flags, topology discovery, JSON output, `run`, and `send-text`.
- [x] 6.5 Run focused control-plane, app-shell, terminal bridge, hook, and CLI tests for the implemented automation paths.
- [x] 6.6 Run `openspec validate automation-targeting-hooks --strict`.
