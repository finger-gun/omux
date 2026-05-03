## Context

OpenMUX already models each pane with a `SessionDescriptor.workingDirectory` and translates Ghostty `PWD` actions into OpenMUX-native terminal actions. The failure mode is that durable workspace state can retain the original workspace root for every pane when the user's later `cd` operations are not reflected in the persisted pane/session model.

The fix crosses the workspace controller, terminal action dispatch, persistence, and pane creation paths, but it should not introduce a new subsystem or expose libghostty details outside `OmuxTerminalBridge`.

## Goals / Non-Goals

**Goals:**
- Treat the latest known pane cwd as durable pane/session state.
- Restore every pane using its own persisted cwd.
- Make tabs, splits, and pane tabs inherit cwd from the relevant focused/source pane where possible.
- Cover multiple workspaces with distinct pane directories in tests.

**Non-Goals:**
- Restoring live processes or terminal scrollback.
- Adding background polling or a daemon.
- Changing keyboard/input semantics or shell command behavior.
- Exposing Ghostty APIs outside the bridge.

## Decisions

1. **Use `Pane.session.workingDirectory` as the durable cwd source.**
   - Rationale: it is already part of the OpenMUX-native model and persistence snapshot.
   - Alternative considered: persist `PaneTerminalState.reportedWorkingDirectory`. Rejected because terminal state is intentionally sanitized on restore for transient UI state, while cwd is session-launch state.

2. **Update durable cwd from terminal cwd actions.**
   - Rationale: Ghostty's `PWD` action is the engine-supported signal for shell cwd changes.
   - Alternative considered: infer cwd by injecting `pwd` commands or parsing prompt text. Rejected as intrusive, shell-specific, and unreliable.

3. **Do not silently substitute workspace root during restore.**
   - Rationale: pane-level cwd is more precise than workspace root and must win when available.
   - Alternative considered: always reset panes to `Workspace.rootPath`. Rejected because it causes the reported bug.

4. **Keep workspace root as workspace metadata, not a proxy for every pane.**
   - Rationale: users can have panes in different directories within one workspace. Workspace root remains useful for default creation and labels, but pane cwd is authoritative for pane relaunch.

## Risks / Trade-offs

- [Shell integration unavailable] → If no cwd event is emitted, OpenMUX can only persist the last known launch cwd. Tests should cover supported event handling, and UX should not fabricate cwd.
- [Stale saved state] → Existing corrupted snapshots may already contain wrong cwd values. The fix prevents future corruption but cannot recover unknown past directories.
- [Workspace root ambiguity] → A workspace created with "New Workspace" may retain the active root until a better workspace creation flow exists. Pane-level cwd persistence still fixes restored panes after cwd events are captured.

## Migration Plan

No data migration is required. Existing snapshots decode unchanged. After the fix, subsequent cwd actions and saves update pane session cwd values in the existing schema.

## Open Questions

- Should a future workspace creation command prompt for or infer a new workspace root? That is separate from preserving pane cwd.
