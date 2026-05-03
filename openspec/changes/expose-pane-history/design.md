## Context

OpenMUX now has a bridge-level ability to read bounded terminal text from live hosted terminal surfaces, but rendered restore for that text is paused because it cannot faithfully reinsert history into Ghostty's buffer and UI overlays degrade the terminal-first experience. The useful capability is explicit, on-demand inspection: a user, hook handler, or script should be able to ask the running app for per-pane history without coupling to app internals or Ghostty APIs.

Existing control-plane commands already expose OpenMUX-native topology, target resolution, and terminal actions over JSON-RPC on a local Unix socket. The history feature should extend that same boundary rather than adding a second transport or background recorder.

## Goals / Non-Goals

**Goals:**

- Add `omux history`, `omux history <pane-id>`, and `omux history all`.
- Add a local JSON-RPC operation that returns bounded terminal history grouped with workspace, tab, pane, and session metadata.
- Make the command safe for hook handlers and shell scripts to call.
- Preserve the terminal bridge boundary by keeping libghostty capture details inside `OmuxTerminalBridge`.
- Bound reads by lines and bytes so large scrollback buffers do not stall the app or flood hook scripts.
- Persist a bounded per-pane/pane-tab history snapshot with workspace state so `omux history` remains useful after app restart.

**Non-Goals:**

- Restore scrollback inside Ghostty or make restarted panes appear as if their old PTY session is still alive.
- Render historical text in OpenMUX pane chrome.
- Send historical text back to a shell through terminal input APIs.
- Restore persisted scrollback into the visible terminal UI.
- Add a daemon, database, tmux/zellij dependency, browser view, or external service.

## Decisions

1. **Use the existing control plane as the source of truth.**
   - Decision: Add a history request/response method to `OmuxControlPlane` and have `omux history` call it.
   - Rationale: This matches existing CLI automation patterns and keeps the app as the authority for live workspace topology.
   - Alternative considered: Let the CLI read app memory or persistence files directly. Rejected because it bypasses the public boundary and cannot access live terminal surfaces safely.

2. **Target by scope, not by Ghostty surface.**
   - Decision: The request accepts OpenMUX scopes: active workspace, pane ID, and all workspaces. Responses include workspace/tab/pane/session IDs and human names/titles where available.
   - Rationale: Users and hooks operate on OpenMUX objects; Ghostty surface IDs are implementation details.
   - Alternative considered: Expose runtime surface IDs for precision. Rejected because it leaks bridge internals and makes hooks brittle.

3. **Default command reads active workspace panes.**
   - Decision: `omux history` with no positional argument reads all panes in the currently active workspace. `omux history <pane-id>` reads exactly one pane, and `omux history all` reads every live pane.
   - Rationale: The user asked for no-arg history to list current panes and `all` to expand across all workspaces. Active workspace is the clearest CLI meaning of "current" in a desktop app.
   - Alternative considered: Default to the focused pane only. Rejected because it would not match "list current panes history".

4. **Return bounded snapshots with explicit availability metadata.**
   - Decision: Each pane history item includes `text`, `lineCount`, `byteCount`, `truncated`, and an `unavailable` reason when neither persisted nor live capture can provide text.
   - Rationale: Automation should not infer missing history from empty text, and callers need to know whether output was truncated.
   - Alternative considered: Return raw text only. Rejected because multi-pane output needs topology and diagnostics.

5. **Provide JSON for scripts and readable output for humans.**
   - Decision: The control-plane response is structured JSON. The CLI prints a readable grouped format by default and supports a JSON output mode consistent with existing automation needs.
   - Rationale: History output can be large; humans need headers, while hooks need stable machine-readable fields.
   - Alternative considered: Always print JSON. Rejected because `omux` is also a terminal-first human CLI.

6. **Persist history per pane, not per workspace.**
   - Decision: Persisted history is stored on each `Pane`/terminal record in workspace state and remains associated with that pane ID/session metadata across restore.
   - Rationale: Users need history for the exact terminal/pane-tab they are inspecting; a workspace-level blob would lose targetability and mix unrelated terminal output.
   - Alternative considered: Store one history file per workspace. Rejected because it would blur pane/tab boundaries and make `omux history <pane-id>` unreliable.

7. **Do not automatically include full history in hook payloads.**
   - Decision: Hooks receive identifiers and can call `omux history` when they need current output context. Existing bounded hook output context remains separate.
   - Rationale: Automatically injecting scrollback into every hook payload risks leaking secrets, increasing latency, and bloating event delivery.
   - Alternative considered: Add history text to all command hook payloads. Rejected for privacy and performance reasons.

## Risks / Trade-offs

- **History may contain secrets** -> Keep access local, explicit, bounded, and scoped; store only bounded per-pane history and do not attach it to every hook payload.
- **Large scrollback reads can hurt responsiveness** -> Enforce conservative default `maxLines`/`maxBytes` limits and let callers request different bounds within implementation-defined caps.
- **Live surface may be unavailable** -> Return an explicit unavailable reason per pane instead of failing the whole multi-pane request when possible.
- **CLI output can be hard to parse if mixed with headers** -> Provide a JSON mode for scripts and hooks.
- **The capture is not session restore** -> Name and document the feature as history/snapshot access, not restored terminal state.

## Migration Plan

1. Add the control-plane request and response types without changing existing methods.
2. Wire app-shell history resolution to live workspace topology and bridge snapshot calls.
3. Add `omux history` CLI handling and usage text.
4. Add tests for default, pane-specific, all-workspace, bounded, unavailable, and JSON behavior.
5. Keep workspace scrollback rendering disabled while persisting bounded per-pane history for CLI/control-plane access.

Rollback is removing the new CLI command and control-plane method; existing workspace, hook, and terminal behavior remains unchanged.

## Open Questions

- Exact default and maximum byte/line limits can be selected during implementation based on existing bridge tests and performance behavior.
