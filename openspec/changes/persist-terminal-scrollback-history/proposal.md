## Why

OpenMUX can restore panes and workspaces after restart, but terminal scrollback disappears even when the pane layout returns. Bounded scrollback restoration gives developers useful recent context without pretending that live processes or terminal applications survived restart.

## Goals

- Persist bounded per-pane terminal scrollback text before shutdown or state save.
- Restore that text as historical context when panes are recreated.
- Clearly scope the feature to scrollback/transcript context, not live session resurrection.
- Keep terminal-engine text extraction behind the OpenMUX terminal bridge boundary.
- Use size-bounded storage so persistence remains performance-conscious.

## Non-goals

- Restoring running commands, TUI/editor state, SSH connections, PTY process identity, or alternate-screen application state.
- Persisting unbounded terminal history.
- Making scrollback a browser/webview-rendered terminal replacement.
- Exposing raw Ghostty APIs or terminal-engine structs to app shell, CLI, hooks, or specs outside the bridge.
- Changing keyboard/input behavior.

## What Changes

- Add a bounded scrollback snapshot concept for pane terminal state.
- Extend terminal bridge abstractions so higher layers can request OpenMUX-native scrollback snapshots from hosted terminal surfaces.
- Persist scrollback snapshots alongside pane/session persistence with explicit limits.
- Restore saved scrollback as historical context for newly attached fresh sessions.
- Add tests for bounds, restore behavior, and the distinction between restored scrollback and live process/session state.

## Capabilities

### New Capabilities

- `terminal-scrollback-persistence`: Bounded per-pane terminal scrollback capture and restoration across app restart.

### Modified Capabilities

- `terminal-bridge`: Bridge exposes bounded terminal text snapshots through OpenMUX-native abstractions while keeping engine-specific APIs localized.
- `ghostty-surface-hosting`: Hosted Ghostty surfaces can provide bounded scrollback snapshots for persistence without transferring surface ownership to the app shell.

## Impact

- Affected code: terminal bridge/runtime snapshot APIs, pane terminal state model, workspace persistence, restore rendering/hosting path, tests.
- Affected behavior: restored panes may show prior scrollback context while starting a fresh shell process in the saved cwd.
- Storage impact: persisted workspace state grows by bounded scrollback text per pane; limits are required.
- UX impact: restored scrollback must not imply that previous processes are still running.
- API impact: no breaking CLI/RPC changes are expected for the first implementation.
- Input impact: none. No key handling, IME, dead-key, compose, or Option/Alt behavior changes are intended.
- Bridge impact: raw `libghostty` text-reading APIs remain confined to `OmuxTerminalBridge`.
