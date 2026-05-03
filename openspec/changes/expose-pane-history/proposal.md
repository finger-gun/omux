## Why

OpenMUX can capture bounded terminal text through the terminal bridge, but there is no clean terminal-first way for users, hooks, or automation to inspect that history without rendering it into pane UI. Developers need an explicit, scriptable history surface so terminal output can be reused by hooks and CLI workflows while preserving a clean native terminal experience.

## Goals

- Expose pane scrollback/history through the local `omux` CLI and JSON-RPC control plane.
- Make history access targetable by OpenMUX-native identifiers: focused workspace, pane ID, and all workspaces/tabs/panes.
- Keep history access useful for external hook scripts without adding UI chrome or pretending historical text is live session state.
- Keep libghostty-specific text capture behind `OmuxTerminalBridge`.

## Non-goals

- Do not render restored history into pane chrome or live terminal UI.
- Do not seed Ghostty's internal terminal buffer or send historical text to a live shell as input.
- Do not introduce a background PTY/session daemon, browser-heavy UI, or monolithic history database.
- Do not provide full process/session restore across app or computer restarts.

## What Changes

- Add an `omux history` command:
  - `omux history` returns bounded history for panes in the active workspace.
  - `omux history <pane-id>` returns bounded history for one pane.
  - `omux history all` returns bounded history for all panes across all workspaces/tabs.
- Add a local control-plane operation for bounded pane-history reads.
- Shape history responses as OpenMUX-native workspace/tab/pane/session records with text, truncation/unavailable metadata, and working directory where available.
- Make the command suitable for hook handlers and scripts to call without depending on private app internals.
- Preserve current UI behavior: history is inspectable via CLI/control plane, not rendered in pane chrome.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `omux-control-plane`: Add a history-read operation and CLI behavior for `omux history`.
- `hooks-foundation`: Clarify that hook handlers can fetch bounded terminal history through the public `omux history`/control-plane contract.
- `terminal-bridge`: Require the bridge to provide bounded terminal text snapshots without leaking Ghostty types outside the bridge.

## Impact

- Affected code: `OmuxCLI`, `OmuxControlPlane`, `OmuxAppShell`, `OmuxTerminalBridge`, and tests.
- APIs: Adds a local JSON-RPC method and CLI command; no breaking changes to existing CLI commands.
- Extension points: Hook scripts gain a stable public way to inspect history by invoking `omux history`.
- Input/keyboard: No keyboard input behavior changes; historical text MUST NOT be sent as terminal input.
- Performance: History reads are bounded and on-demand only; no background recorder or persistent history database is introduced.
