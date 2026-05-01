## Why

OpenMUX currently ignores every `libghostty` action upcall, which keeps the embedding boundary safe but leaves important terminal behavior unavailable: pane titles do not track commands, cwd changes do not surface, command completion cannot drive automation, and host behaviors like URL opening or desktop notifications are dropped. This matters now because OpenMUX already has the bridge, native shell, hooks, and local control plane needed to turn selected actions into OpenMUX-native behavior without giving Ghostty ownership of the app shell.

## Goals

- Honor a focused first wave of high-value Ghostty actions that improve terminal fidelity and automation.
- Preserve the bridge boundary by translating Ghostty actions into OpenMUX-native concepts before they leave `OmuxTerminalBridge`.
- Establish a structured event payload model that can support hooks, diagnostics, and future control-plane event delivery without stringly typed flattening.
- Keep OpenMUX terminal-first by treating app-shell actions as OpenMUX-owned behavior and session/host actions as terminal signals worth surfacing.

## Non-goals

- Adopting Ghostty's app-shell model for windows, tabs, splits, fullscreen, config UX, or updates.
- Implementing every Ghostty action in one change.
- Building a distributed event system or long-running background service.
- Reworking keyboard/input dispatch; key-sequence and key-table actions remain part of the input pipeline design space.

## What Changes

- Add an OpenMUX-native terminal action/event model inside the bridge that classifies Ghostty actions into reject, honor, or defer buckets.
- Honor a first wave of session and host actions: `PWD`, `SET_TITLE`, `SET_TAB_TITLE`, `OPEN_URL`, `DESKTOP_NOTIFICATION`, `RING_BELL`, `COMMAND_FINISHED`, `PROGRESS_REPORT`, `SHOW_CHILD_EXITED`, and `RENDERER_HEALTH`.
- Route honored actions into OpenMUX-owned outcomes: pane/tab chrome updates, native macOS notifications and URL opening, pane/session status, and automation-facing events.
- **BREAKING (pre-release):** replace string-only hook metadata for dispatched terminal events with a structured OpenMUX-native payload value so rich event bodies do not have to be flattened into `[String: String]`.
- Extend the control-plane design to define OpenMUX-native terminal event semantics for future subscribers while keeping the current request/response command boundary lightweight and local-first.
- Keep Ghostty app-shell actions such as new window/tab/split, fullscreen, config, and update requests rejected by default.
- Treat Ghostty and cmux only as clean-room behavioral inspiration; no upstream app-shell code or GPL code is adopted.

## Capabilities

### New Capabilities
- `terminal-action-dispatch`: Defines how terminal-engine upcalls are translated into OpenMUX-native actions/events, classified, and routed to shell, hooks, and control-plane surfaces.

### Modified Capabilities
- `terminal-bridge`: The bridge now translates selected Ghostty actions into OpenMUX-native action/event values while keeping Ghostty types confined to the bridge module.
- `hooks-foundation`: Hook payload requirements change from string-only metadata to structured OpenMUX-native event payloads for automation-facing terminal events.
- `omux-control-plane`: The control-plane contract gains terminal-event semantics so external tools can consume OpenMUX-native terminal events without depending on Ghostty details.
- `macos-app-shell`: The native shell gains requirements to surface terminal-driven title, notification, bell, progress, and child-exit state without giving layout ownership to the engine.

## Impact

- **Code**:
  - `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift` and related bridge types for `action_cb` handling, action translation, and dispatch.
  - `Sources/OmuxHooks` for structured hook payload contracts.
  - `Sources/OmuxControlPlane` for terminal-event contract additions.
  - `Sources/OmuxAppShell` for pane/tab chrome updates, notifications, bell/progress UI, and session-ended state.
- **APIs and contracts**:
  - Hook invocation payload shape changes.
  - New OpenMUX-native terminal action/event types are introduced below the bridge boundary.
  - Control-plane event semantics are defined in OpenMUX terms, not Ghostty enums.
- **Dependencies**:
  - No new background service or browser-heavy surface.
  - No direct Ghostty type leakage outside `OmuxTerminalBridge`.
- **Manifest alignment**:
  - *Terminal first*: restores expected terminal/session behavior instead of adding unrelated shell complexity.
  - *Open by design* and *hackable*: turns terminal actions into explicit automation-friendly contracts for hooks and future subscribers.
  - *Performance-conscious*: keeps dispatch local, synchronous where appropriate, and free of unnecessary daemons.
  - *Bridge boundary*: preserves the narrow libghostty seam.
- **Keyboard/input correctness**:
  - This change does not alter key normalization or layout handling; actions tied to multi-key input state stay deferred to `input-pipeline`.
