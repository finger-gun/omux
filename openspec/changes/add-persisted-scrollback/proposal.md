## Why

OpenMUX already saves bounded per-pane terminal text as historical context, but restored panes still open visually empty because that history is not replayed into the fresh terminal surface. Persisted, visually restored scrollback makes OpenMUX feel like a continuous terminal workspace across app restarts while preserving the honest boundary that live PTY/process state is not restored.

## Goals

- Restore useful per-pane terminal scrollback visually after restart by replaying saved raw terminal output before the first shell prompt.
- Preserve ANSI colors and formatting where safe so restored history resembles the original terminal output.
- Enable persisted scrollback by default with configurable limits, defaulting to 4,000 lines.
- Move workspace/session persistence toward Application Support files instead of long-term `UserDefaults` storage for large or durable session data.
- Keep the libghostty integration localized behind the terminal bridge and expose only OpenMUX-native persistence/replay concepts outside it.

## Non-goals

- Restoring live PTY state, running commands, SSH connections, TUI process state, or exact scroll position.
- Loading or mutating Ghostty's own history files or user Ghostty configuration.
- Adding a browser-heavy persistence layer, daemon, cloud sync, or external service.
- Exposing persisted scrollback to hooks or plugin payloads by default.
- Copying CMUX implementation code or file structure; CMUX is clean-room behavioral inspiration only.

## What Changes

- Add file-backed workspace/session persistence under Application Support with migration from the existing `UserDefaults` snapshot.
- Store bounded per-pane scrollback payloads separately from large JSON/defaults blobs.
- Add user-facing persisted scrollback configuration, enabled by default with a 4,000-line default retention limit and a protective byte cap.
- Add explicit layout-only versus scrollback-inclusive snapshot modes so frequent persistence stays cheap while scrollback saves run on termination and slower background cadence.
- Add terminal launch environment plumbing so restored panes can pass replay metadata through the Ghostty bridge.
- Add wrapper-command visual replay for restored panes: replay raw ANSI output from a local replay file before shell startup, reset formatting, clean up the replay file, then `exec` the user's shell as a login shell.
- Define stable best-effort behavior for alternate-screen/full-screen TUI output without claiming process restoration.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `terminal-scrollback-persistence`: Add default-on visual replay, raw ANSI preservation, configurable 4,000-line retention, file-backed payload storage, and best-effort alternate-screen behavior.
- `terminal-bridge`: Add OpenMUX-native terminal launch environment/replay plumbing while keeping Ghostty types confined to the bridge.
- `config-system`: Add persisted scrollback settings to the user-facing configuration surface.

## Impact

- `OmuxCore`: scrollback snapshot bounds, persistence/replay metadata, and workspace model compatibility.
- `OmuxConfig`: persisted scrollback configuration parsing, defaults, template, CLI rendering, and diagnostics.
- `OmuxAppShell`: workspace persistence store, snapshot scheduling modes, restore orchestration, Application Support migration, and slow scrollback-inclusive autosaves.
- `OmuxTerminalBridge`: Ghostty surface environment propagation and restored-pane wrapper launch behavior.
- Tests: config parsing/rendering, file-store migration, snapshot bounds, save-mode behavior, replay-file creation/cleanup, environment propagation, and restored history behavior.
- Documentation: configuration docs and user-facing explanation that restored scrollback is best-effort history, not live process restoration.
