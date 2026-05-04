## Context

OpenMUX now has the important pieces around runtime terminal state: a pinned Ghostty runtime behind `OmuxTerminalBridge`, AppKit-hosted pane surfaces, bounded scrollback capture, workspace persistence, `omux history`, terminal action dispatch, hooks, and control-plane events. The weak link is the live `TerminalSessionSnapshot` path: it can report shell, working directory, and size, but its text fields are still minimal placeholders.

That creates an architectural mismatch. Runtime text can already be read for history/persistence, but command completion enrichment and snapshot observers still reason through a snapshot shape whose rendered text may be empty. The result is a terminal-first app that can host a real terminal but cannot consistently describe the visible or recent terminal text to its own automation surfaces.

The design must preserve the core boundary rule: all direct Ghostty text APIs stay inside `OmuxTerminalBridge`; app shell, hooks, CLI, and control-plane code consume OpenMUX-native snapshot/history/output-context values only.

## Goals / Non-Goals

**Goals:**

- Make runtime-backed `TerminalSessionSnapshot` text meaningful when the runtime can provide bounded terminal text.
- Share one bounded terminal text capture path across live snapshots, command completion output context, history requests, and persistence.
- Represent unavailable text explicitly so callers do not confuse "no output" with "capture failed".
- Preserve local-only, bounded-by-default behavior for persisted scrollback.
- Keep the design performance-safe by avoiding unbounded transcript buffering, polling, or background indexing.

**Non-Goals:**

- Restoring live PTY/process state after restart.
- Building a searchable transcript database or long-term output index.
- Exposing persisted scrollback to hooks by default.
- Adding plugin runtime behavior, browser surfaces, cloud sync, or AI-specific privileged paths.
- Changing keyboard/input semantics. This change reads terminal output only; it does not alter key routing, Option/Alt behavior, dead keys, compose keys, or IME handling.

## Decisions

### 1. Treat bounded terminal text as a bridge-owned product value

The bridge should expose a single OpenMUX-native bounded text result that can represent:

- available text,
- whether the returned text was truncated,
- the caller's line/byte limits, and
- an explicit unavailable reason.

The implementation can continue to use Ghostty text extraction internally, but the result type should not expose Ghostty points, selections, buffers, or raw C structs.

**Alternatives considered:**

- **Expose Ghostty text concepts to callers**: rejected because it violates the bridge boundary and couples app-shell/control-plane code to an unstable upstream API.
- **Keep separate text paths for snapshot, history, and persistence**: rejected because it risks inconsistent truncation, unavailable-state, and restore behavior.

### 2. Populate live snapshots from bounded runtime text, not an unbounded transcript buffer

Runtime snapshots should be assembled on demand from the hosted surface. The snapshot should prefer the same capture order already used for history where appropriate: scrollback/history plus active text when available, then screen/viewport fallbacks if broader capture is unavailable.

The snapshot remains a bounded moment-in-time view. It is not a promise that OpenMUX has retained the entire terminal transcript.

**Alternatives considered:**

- **Maintain a parallel transcript buffer in app shell**: rejected because it duplicates terminal-engine state, increases memory pressure, and risks diverging from what the runtime actually renders.
- **Only use screen text**: rejected because command-finished output context and persistence are more useful when recent scrollback is available.

### 3. Make command completion output context consume the improved snapshot/history result

`COMMAND_FINISHED` events should continue to be translated into OpenMUX-native terminal action events first. After translation, app-shell enrichment should attach bounded output context when the bridge can provide text, and otherwise attach an explicit unavailable marker.

This preserves the action-dispatch boundary while making hooks, `omux events`, and future plugins more useful.

**Alternatives considered:**

- **Buffer output per command in the action dispatcher**: rejected for now because shell integration may not reliably identify command boundaries for all shells/TUIs, and unbounded per-command buffers would add complexity.
- **Attach persisted restored scrollback to command events**: rejected because restored scrollback is historical context, not live output from the completed command.

### 4. Keep persistence historical and local

Persistence should store bounded text as historical context only. Restored panes should launch fresh shell sessions and may display or expose the saved historical context through explicit history surfaces, but they must not claim the old process, PTY, SSH connection, or TUI state is still alive.

Hooks emitted during restore should not include persisted scrollback unless a future explicit contract opts into that.

**Alternatives considered:**

- **Persist full transcripts by default**: rejected for privacy, disk usage, and performance reasons.
- **Emit restored scrollback to hooks automatically**: rejected because it would broaden data exposure without an explicit user-facing contract.

### 5. Preserve existing CLI/control-plane shapes where possible

`omux history` and control-plane history responses already have bounded text, count, truncation, and unavailable fields. This change should improve the data source behind those fields rather than force a breaking payload redesign.

If snapshot internals need additional metadata, prefer adding optional fields in OpenMUX-native types over replacing existing public control-plane fields.

## Risks / Trade-offs

- **Ghostty text extraction can be unavailable or incomplete** -> Surface an explicit unavailable result and keep pane metadata intact.
- **Large terminal output can be expensive to copy** -> Enforce caller-supplied byte/line limits and default bounded limits.
- **Screen, viewport, active text, and history can overlap** -> Centralize combination/truncation rules and test duplicate/empty fallback behavior.
- **Restored historical text could be mistaken for live state** -> Keep restore wording and data model explicit: historical context only, fresh shell session.
- **Command-finished output context may include more terminal text than the completed command emitted** -> Document it as bounded output context/tail, not an exact per-command transcript.

## Migration Plan

1. Introduce or refine bridge-owned bounded text result types without changing direct Ghostty ownership.
2. Update `TerminalSessionSnapshot` construction to fill text from the bounded runtime capture path.
3. Route command completion output context through the improved snapshot/history result.
4. Keep persistence and `omux history` using bounded local text and explicit unavailable states.
5. Add unit tests around truncation, unavailable capture, command event payloads, and restore semantics.

Rollback is straightforward: callers can fall back to the existing unavailable/empty snapshot behavior while preserving the bridge and control-plane contracts.

## Open Questions

- Should the eventual UI render restored historical context inline in pane chrome, or should it remain available only through history/control-plane surfaces until a separate UX change?
- Should output context include a stable reference to a larger local history item in the future, or is inline bounded tail text enough for v1?
