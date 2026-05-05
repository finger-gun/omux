## 1. Configuration and Bounds

- [x] 1.1 Add persisted scrollback config values with defaults: enabled, 4,000 lines, and a protective byte cap.
- [x] 1.2 Decode, validate, render, and document persisted scrollback config settings with structured diagnostics for invalid values.
- [x] 1.3 Update `PaneScrollbackSnapshot` bounds to support configurable line and byte limits while preserving existing bounded/combined semantics.

## 2. File-Backed Persistence

- [x] 2.1 Replace canonical workspace persistence writes with an Application Support file-backed store using atomic JSON writes.
- [x] 2.2 Preserve migration/fallback from the existing `UserDefaults` snapshot and retain backup JSON behavior.
- [x] 2.3 Add separate scrollback payload storage under Application Support with restrictive permissions and snapshot references or restore-time resolution.
- [x] 2.4 Add explicit layout-only and scrollback-inclusive snapshot modes so frequent saves can avoid terminal text reads.

## 3. Terminal Replay Bridge

- [x] 3.1 Wire `SessionDescriptor.environment` into `ghostty_surface_config_s.env_vars` and retain C string/env storage for the surface lifetime.
- [x] 3.2 Add an OpenMUX-owned scrollback replay store that writes bounded raw ANSI replay files and cleans stale/consumed files.
- [x] 3.3 Add wrapper-based restored-pane launch that replays `OMUX_RESTORE_SCROLLBACK_FILE`, resets formatting, emits a newline, and execs the user shell as a login shell before the first prompt.
- [x] 3.4 Validate the exact Ghostty embedded command form against the vendored GhosttyKit attach path without leaking Ghostty types outside the bridge.

## 4. Restore Orchestration and History

- [x] 4.1 Restore panes with replay metadata when persisted scrollback exists and persisted scrollback is enabled.
- [x] 4.2 Preserve existing `terminalHistory(...)` restored-scrollback fallback while adding visual replay.
- [x] 4.3 Implement conservative alternate-screen/TUI handling that preserves useful ANSI formatting while avoiding broken prompt state.
- [x] 4.4 Add slow scrollback-inclusive autosave triggers for crash durability plus termination/power/logout full-save paths.

## 5. Validation and Documentation

- [x] 5.1 Add config, bounds, file-store migration, payload storage, replay cleanup, and bridge environment tests.
- [x] 5.2 Add app-shell tests proving layout-only saves skip text capture and scrollback-inclusive saves capture bounded scrollback.
- [x] 5.3 Add restore/replay tests or smoke coverage proving replay occurs before the prompt and does not use shell input.
- [x] 5.4 Update user documentation for persisted scrollback behavior, config settings, privacy implications, and non-restoration of live process state.
- [x] 5.5 Run targeted Swift tests and the full existing Swift test suite.

## 6. History Cleanup

- [x] 6.1 Add `terminal.history.clear` RPC contracts and `omux history clear` CLI with all/pane/pane-tab/tab/workspace/session/focused scopes.
- [x] 6.2 Clear model-level restored scrollback and suppress immediate recapture of unchanged live terminal text for targeted panes.
- [x] 6.3 Prune unreferenced scrollback payload files after history cleanup.
- [x] 6.4 Document history cleanup and add CLI/app-shell/persistence tests.
- [x] 6.5 Clear live Ghostty screen/scrollback for running targeted panes and dedupe repeated replay tail prompt/login noise.
- [x] 6.6 Add active-pane terminal-local clear fallback and sanitize repeated prompt/login noise before persistence writes.
- [x] 6.7 Drop stale trailing prompt-only lines from persisted/replayed scrollback.
