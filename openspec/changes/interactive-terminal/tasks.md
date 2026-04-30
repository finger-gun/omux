## 1. Interactive session runtime

- [x] 1.1 Replace transcript-only pane session state with a bridge-owned persistent interactive session model.
- [x] 1.2 Add PTY-backed shell spawn, streaming output, input writes, resize handling, and teardown inside `OmuxTerminalBridge`.
- [x] 1.3 Add a lightweight rendered screen state that keeps common shell prompts and line refresh behavior readable in pane snapshots.

## 2. Terminal input and pane UX

- [x] 2.1 Update terminal pane hosting so focused panes accept direct typing, focus, paste, and editing input without the Run Command modal.
- [x] 2.2 Route normalized terminal input through bridge-level terminal encoding for return, delete, arrows, composition, and text insertion.
- [x] 2.3 Propagate pane size changes from the AppKit shell to the live session so resizes update the terminal runtime.

## 3. Shared actions and control plane

- [x] 3.1 Change workspace/session actions so `runCommand` injects into the ongoing session instead of launching a one-off subprocess.
- [x] 3.2 Keep `omux` and JSON-RPC aligned with the live interactive session model and preserve session continuity across UI and automation.

## 4. Validation and documentation

- [x] 4.1 Add validation coverage for persistent session continuity, streaming output, teardown, and resize behavior.
- [x] 4.2 Add validation coverage for direct pane input, international keyboard paths, paste/editing keys, and live-session command injection.
- [x] 4.3 Update developer-facing documentation to describe the interactive-terminal baseline, its current limits, and how future UX work should build on it.
