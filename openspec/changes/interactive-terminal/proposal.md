## Why

OpenMUX now shows pane-shaped terminal UI, but it still behaves like a transcript viewer with a modal command prompt rather than a terminal-first workspace. This change is needed now because the current interaction model blocks the core product promise: click a pane, type directly, and stay in one live shell session without UI detours.

## Goals

- Make focused panes accept direct keyboard input without a separate command modal.
- Replace one-off command execution with persistent interactive shell sessions per pane.
- Keep terminal lifecycle, PTY ownership, and rendering coordination behind the existing terminal bridge boundary.
- Preserve the normalized input pipeline so Option/Alt, right-Option, dead keys, and composition paths remain correct in live terminal panes.
- Improve the baseline UX enough that future shell chrome can build on a real terminal instead of a simulated one.

## Non-goals

- Building the full `docs/vision.png` chrome, sidebar, or event timeline in this change.
- Adding browser-based UI, background daemons, or vendor-specific integrations.
- Introducing an embedded plugin runtime or changing the local-first JSON-RPC architecture.
- Reproducing code from GPL projects; any inspiration remains clean-room and behavioral only.

## What Changes

- Replace transcript-style pane interaction with a real interactive terminal session model that keeps a shell alive per pane.
- Remove the modal-only command entry path as the primary way to use a pane; typing in the pane becomes the default interaction.
- Extend terminal pane hosting so focused panes handle text input, return, editing keys, paste, resize, and focus changes like a usable native terminal.
- Update shared workspace/session actions so UI and `omux` target the same live session objects instead of one-off command execution state.
- Strengthen input-path guarantees for international layouts and composition-sensitive flows in live terminal panes.

## Capabilities

### New Capabilities
- `interactive-terminal-sessions`: Persistent pane-owned interactive shell sessions and terminal I/O behavior for the first usable terminal UX.

### Modified Capabilities
- `terminal-bridge`: Expand the bridge requirements from surface/session ownership to persistent interactive PTY/session coordination.
- `terminal-pane-hosting`: Change pane-hosting requirements so visible panes are directly interactive, focusable, and usable without modal command entry.
- `workspace-session-actions`: Change workspace/session actions to operate on persistent live sessions rather than transcript-style command submission.
- `input-pipeline`: Extend input guarantees so normalized text input, editing keys, paste, and composition-sensitive flows work in interactive panes.

## Impact

- Affected code: `OmuxTerminalBridge`, `OmuxAppShell`, `OmuxCore`, `OmuxControlPlane`, `OmuxCLI`, and related tests.
- Affected UX: pane focus, direct typing, command execution, paste/editing behavior, and session continuity across tabs and splits.
- Affected dependencies/systems: terminal runtime integration, shell process lifecycle, PTY/session ownership, and local control-plane behavior.
- Architecture impact: preserves AppKit-first UI, keeps libghostty isolated behind the bridge, and avoids browser-heavy or monolithic expansion while moving closer to the manifesto’s terminal-first baseline.
