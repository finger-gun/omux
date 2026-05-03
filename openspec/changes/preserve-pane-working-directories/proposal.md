## Why

OpenMUX currently restores workspace and pane structure after restart, but panes can relaunch in the wrong directory when users create workspaces or panes and then `cd` inside the terminal. For a terminal-first workspace, the current directory is core session context; losing it makes restored workspaces feel unreliable and collapses distinct project workspaces into the same root.

## Goals

- Persist each pane's latest known working directory across app restart.
- Restore each terminal pane using its own saved working directory rather than only the workspace root.
- Keep new tabs, splits, and pane tabs inheriting the relevant focused pane or workspace cwd predictably.
- Preserve the `libghostty` bridge boundary by translating engine cwd signals into OpenMUX-native pane/session state.

## Non-goals

- Restoring live processes, TUI state, SSH sessions, or shell process identity.
- Adding browser/webview architecture, background daemons, or terminal-engine-specific state outside the bridge.
- Changing keyboard/input handling semantics.
- Implementing terminal scrollback restoration; that is covered by a separate improvement.

## What Changes

- Update the workspace/session behavior contract so a pane's persisted cwd follows the terminal's reported cwd.
- Ensure restored panes attach terminal sessions with their saved per-pane cwd.
- Ensure pane creation actions use the latest focused pane cwd when creating related panes.
- Strengthen tests around multiple workspaces and panes with distinct directories.
- Keep cwd updates observable through existing terminal action dispatch and OpenMUX-native state, without exposing Ghostty types outside `OmuxTerminalBridge`.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `workspace-session-actions`: Pane/session actions preserve and reuse per-pane working directory context.
- `terminal-action-dispatch`: Terminal cwd actions update durable OpenMUX pane/session state.

## Impact

- Affected code: `WorkspaceController`, workspace persistence, terminal action coordination, app shell tests, terminal action tests.
- Affected behavior: restored panes start in their last known cwd; new panes derive cwd from the focused pane or explicit workspace path.
- API impact: no breaking CLI/RPC changes are expected; existing workspace/session payloads continue to use OpenMUX-native identifiers and values.
- Extension impact: hooks and control-plane events continue to receive OpenMUX-native cwd payloads. The fix makes those payloads more reliable.
- Input impact: none. No key handling, IME, dead-key, compose, or Option/Alt behavior changes are intended.
- Bridge impact: `libghostty` remains behind `OmuxTerminalBridge`; cwd upcalls continue to be translated into OpenMUX-native terminal actions.
