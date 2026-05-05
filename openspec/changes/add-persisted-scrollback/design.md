## Context

OpenMUX already has the core model pieces for persisted scrollback: `PaneScrollbackSnapshot`, `PaneTerminalState.restoredScrollback`, bridge-owned bounded terminal text snapshots, and workspace restore logic that preserves restored scrollback in the model. The missing product behavior is visual restoration: after restart, a pane starts a fresh shell but the saved scrollback is not replayed into the terminal surface before the prompt.

The current persistence store writes the workspace snapshot into `UserDefaults` and creates JSON backups under Application Support. That is acceptable for small metadata, but persisted terminal scrollback is larger, potentially sensitive, and should live in an inspectable file-backed session store with atomic writes and restrictive permissions. This change also touches the terminal bridge because Ghostty launch environment and command wiring must stay behind the narrow bridge boundary.

CMUX is useful clean-room behavioral inspiration: it treats scrollback restoration as best-effort raw terminal-output replay, not libghostty state serialization or PTY resurrection. OpenMUX should implement the behavior using its own types, storage layout, and bridge contracts.

## Goals / Non-Goals

**Goals:**

- Persist per-pane scrollback by default with a configurable 4,000-line default retention limit and protective byte cap.
- Preserve raw ANSI formatting where safe so restored output keeps colors and styling.
- Visually replay restored scrollback before the first interactive shell prompt.
- Keep restored panes honest: fresh shell/process state with historical output replayed above the prompt.
- Move durable workspace/session persistence to Application Support files and migrate existing `UserDefaults` snapshots.
- Keep libghostty details confined to `OmuxTerminalBridge`.

**Non-Goals:**

- Restoring live PTY state, running processes, SSH connections, TUI process state, or exact scroll position.
- Reading Ghostty user configuration or depending on Ghostty private history files.
- Exposing persisted scrollback to hooks, plugins, or control-plane events by default.
- Adding daemons, cloud sync, database dependencies, or browser-backed persistence.

## Decisions

### Store session state in Application Support files

OpenMUX will introduce a file-backed workspace/session store under Application Support:

```text
~/Library/Application Support/OpenMUX/
  WorkspaceState/
    current.json
    previous.json
  Scrollback/
    <workspace-id>/<pane-id>.ansi
  Replay/
    <uuid>.ansi
  WorkspaceBackups/
    workspace-<timestamp>-<uuid>.json
```

`current.json` remains the small canonical workspace/session snapshot. Large scrollback payloads are stored separately and referenced from the snapshot. The existing `UserDefaults` snapshot is treated as a migration source: load it if no file-backed snapshot exists, then save through the file store and leave future reads on the file-backed path.

Alternative considered: keep all workspace persistence in `UserDefaults`. Rejected because scrollback payloads are large, user-inspectable state belongs in Application Support, and file storage gives better atomicity, backups, and cleanup control.

### Make save modes explicit

Workspace persistence will distinguish layout-only saves from scrollback-inclusive saves. Layout-only saves remain cheap and can run frequently after workspace/model changes. Scrollback-inclusive saves run on termination/power/logout events and a slower background cadence to improve crash durability without repeatedly reading terminal text on every layout update.

Alternative considered: include scrollback in every save. Rejected because terminal text extraction may be expensive and would couple frequent UI/model changes to scrollback reads.

### Use raw ANSI payloads with reset protection

Scrollback payloads store raw terminal output returned by the bridge, including ANSI escape sequences where available. Replay files are bounded by line and byte limits and should end with terminal reset/newline protection before the prompt appears.

Alternative considered: sanitize to plain text. Rejected because colors, styling, and command output formatting are part of the terminal UX; plain text replay would make restored history feel broken.

### Replay through an OpenMUX-owned wrapper command

Restored panes with scrollback launch an OpenMUX-owned wrapper as the terminal command. The wrapper reads `OMUX_RESTORE_SCROLLBACK_FILE`, writes it to stdout before shell startup, deletes the replay file, emits `ESC[0m` and a newline, then `exec`s the user's shell as a login shell.

Conceptual wrapper:

```sh
#!/bin/sh
if [ -n "$OMUX_RESTORE_SCROLLBACK_FILE" ] && [ -r "$OMUX_RESTORE_SCROLLBACK_FILE" ]; then
  cat "$OMUX_RESTORE_SCROLLBACK_FILE"
  rm -f "$OMUX_RESTORE_SCROLLBACK_FILE"
fi
printf '\033[0m'
printf '\n'
exec "${SHELL:-/bin/sh}" -l
```

Because the wrapper runs as the launched command, replay occurs before shell startup and before the prompt is drawn. The terminal bridge will pass environment variables through `ghostty_surface_config_s.env_vars`, and the restored session command will be set to the wrapper command form accepted by the vendored GhosttyKit integration. The embedded Ghostty surface `command` option currently always runs through shell command handling, so OpenMUX must shell-quote the wrapper path instead of using Ghostty's config-file-only `direct:` prefix.

The bridge should avoid compounding active-screen overlap when combining surface and active text snapshots. Replay preparation also performs conservative tail cleanup for visually duplicate ANSI prompt lines so empty/restored panes do not accumulate repeated prompt tails across launches.

Alternative considered: use `initial_input`. Rejected because it is shell-visible, can pollute shell history, and runs too late for clean pre-prompt replay.

### Treat alternate-screen/TUI output as best effort

OpenMUX will not attempt to reconstruct alternate-screen process state. It will replay useful captured output with reset protection and prefer a stable, readable prompt over exact TUI reconstruction. If bridge capture cannot safely provide useful raw output for an alternate-screen state, persistence may preserve previous restored context or omit new scrollback rather than fabricate broken output.

### Expose explicit history cleanup

Persisted scrollback can contain sensitive output. In addition to config opt-out, OpenMUX exposes `omux history clear` through the control plane so users can remove saved scrollback without manually editing Application Support files. The default clears all panes, and scoped cleanup can target a pane/pane-tab, top-level tab, workspace, session, or focused pane. Clearing history removes model-level restored scrollback immediately, asks Ghostty to clear live screen/scrollback for running panes when available, prunes unreferenced payload files on the next persistence write, and suppresses immediate recapture of unchanged live terminal text so the clear remains durable. OpenMUX-launched shells also receive pane/session environment identifiers; when `omux history clear` is run from a targeted OpenMUX pane, the CLI emits terminal erase sequences locally after the control-plane clear succeeds so the invoking pane's visible buffer clears even if the runtime action is delayed.

Repeated prompt-only tails can accumulate because restored visual history is replayed before each fresh login shell draws its own login banner and prompt. OpenMUX sanitizes replay files and scrollback-inclusive persistence writes with the same tail-only cleanup: repeated `Last login:` lines collapse to the latest occurrence, stale trailing prompt-shaped lines are dropped, and ordinary repeated command output is preserved.

## Risks / Trade-offs

- Persisted scrollback may contain secrets -> Mitigate with local-only storage, restrictive file permissions, clear documentation, default bounds, and an easy opt-out.
- Raw ANSI replay may include unsafe terminal state transitions -> Mitigate with bounding, reset/newline protection, and conservative capture/replay tests for alternate-screen cases.
- Wrapper command could alter shell startup semantics -> Mitigate by using `exec`, preserving the user's shell path, launching as a login shell, and testing common zsh/bash cases.
- File migration could lose existing workspace state -> Mitigate by treating `UserDefaults` as fallback/migration source and preserving backup JSON behavior.
- Scrollback-inclusive autosaves could affect performance -> Mitigate with explicit save modes and a slow debounce/cadence.

## Migration Plan

1. Add file-backed store while retaining the ability to read the existing `UserDefaults` snapshot.
2. On first successful file-backed load/save, migrate the existing snapshot into Application Support.
3. Continue writing backups before replacing current state.
4. Keep restore tolerant of missing scrollback payload files by restoring layout/session metadata and omitting unavailable history.
5. If rollout needs rollback, the app can still read the existing `UserDefaults` snapshot until the migration path is removed in a later change.

## Open Questions

- The exact Ghostty command string/direct form must be validated against the vendored GhosttyKit bridge during implementation.
- The final default byte cap should be confirmed in tests; the design expects a protective cap large enough for 4,000 typical terminal lines.
