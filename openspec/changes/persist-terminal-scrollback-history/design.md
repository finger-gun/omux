## Context

OpenMUX currently restores workspace layout and terminal session launch directories, but terminal scrollback is lost because runtime snapshots return empty transcript/current-input fields. The pinned Ghostty C API exposes text-reading primitives for surface text, so OpenMUX can add a bounded scrollback snapshot behind the terminal bridge boundary.

This change is intentionally about historical text context only. Restored panes start fresh shell processes; prior output is context, not proof that previous commands or processes still exist.

## Goals / Non-Goals

**Goals:**
- Capture bounded per-pane scrollback text through OpenMUX-native bridge APIs.
- Persist scrollback snapshots with explicit size/line limits.
- Restore scrollback as historical context distinct from fresh live output.
- Keep raw Ghostty text APIs inside `OmuxTerminalBridge`.

**Non-Goals:**
- Restoring live processes, PTY state, SSH sessions, alternate screen apps, or running commands.
- Persisting unbounded scrollback.
- Replacing Ghostty rendering with a browser or custom terminal emulator.
- Exposing scrollback text automatically to hooks or external services.

## Decisions

1. **Represent scrollback as bounded text metadata on pane terminal state.**
   - Rationale: scrollback is pane-local historical context and should travel with pane persistence.
   - Alternative considered: store scrollback in a global log. Rejected because it complicates retention and pane identity.

2. **Request scrollback through a bridge snapshot API.**
   - Rationale: Ghostty APIs must remain localized, and higher layers should consume OpenMUX-native strings/limits.
   - Alternative considered: call Ghostty directly from app shell. Rejected by the bridge boundary rule.

3. **Restore scrollback as historical context, not live terminal buffer state.**
   - Rationale: fresh shells cannot safely be made to believe old output belongs to the current process state.
   - Alternative considered: inject prior output into the terminal input/output stream. Rejected because it would pollute shell state and automation output.

4. **Use conservative bounds by default.**
   - Rationale: workspace persistence uses user defaults today; unbounded text would harm startup and save performance.
   - Alternative considered: unlimited scrollback persistence. Rejected as unsafe.

## Risks / Trade-offs

- [API limitations] → Ghostty may expose text extraction differently than expected; keep implementation behind a bridge method so fallback can return no scrollback.
- [User confusion] → Restored text could look live. Mitigate with explicit state/metadata and, where UI supports it, a restored-context marker.
- [Storage growth] → Bound by bytes/lines per pane and trim before persistence.
- [Sensitive output] → Persisted scrollback may contain secrets. Keep scope local, bounded, and do not expose it through hooks by default.

## Migration Plan

Add optional scrollback fields so existing snapshots decode unchanged. Older snapshots restore with no scrollback context. If capture fails, persistence still saves layout and cwd.

## Open Questions

- What should the first visual marker for restored scrollback look like in the hosted Ghostty surface path?
- Should scrollback persistence be configurable in the first release or introduced with fixed conservative limits?
