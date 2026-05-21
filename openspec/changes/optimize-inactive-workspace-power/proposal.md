## Why

Users have reported OpenMUX showing up as a significant energy consumer while it appears visually idle. For a terminal-first developer workspace, inactive workspaces may still contain agents, web servers, SSH sessions, builds, and other long-running processes, so the fix must reduce presentation/rendering work without suspending terminal sessions or hiding process activity.

## Goals

- Keep inactive workspace terminal sessions, PTYs, child processes, output capture, title changes, progress indicators, bells, and persistence behavior alive.
- Stop or sharply reduce renderer/display work for terminal surfaces that are not user-visible because their workspace, tab, pane stack, modal, or window is inactive, hidden, minimized, or occluded.
- Preserve the libghostty bridge boundary by expressing visibility as an OpenMUX-native surface lifecycle concept and localizing upstream calls inside `OmuxTerminalBridge`.
- Add a repeatable macOS before/after power profile so CPU, memory, thread count, renderer/display-link activity, and process energy can be compared rather than relying only on the battery menu.
- Keep the implementation terminal-first, native AppKit-first, and performance-conscious without introducing background services or browser-heavy architecture.

## Non-goals

- Do not pause, suspend, throttle, or terminate child processes in inactive workspaces.
- Do not disable terminal IO, shell integration, hooks, control-plane events, scrollback capture, or agent/status observation for inactive workspaces.
- Do not replace the terminal renderer, introduce a webview terminal, or move terminal-engine ownership into workspace shell code.
- Do not add a daemon, vendor-specific power monitor, or always-on telemetry service.
- Do not change keyboard/input semantics; inactive surfaces should not become input targets until made visible and focused again.

## What Changes

- Track terminal surface visibility separately from terminal session liveness.
- Mark non-visible hosted terminal surfaces as occluded through the terminal bridge while keeping their sessions and process IO active.
- Un-occlude and refresh a terminal surface when it becomes visible again so the user sees current output without restarting the session.
- Account for inactive workspaces, inactive tabs, hidden pane-stack tabs, floating modal visibility, window minimization, and app/window occlusion when deriving terminal surface presentation state.
- Add a repeatable idle power profile for baseline and regression comparison using local macOS tools such as `ps`, `sample`, `powermetrics`, `top`, and `vmmap`.
- Document the expected behavior: inactive workspace means not visible, not not-running.

## Capabilities

### New Capabilities

- `runtime-power-baselines`: Defines the repeatable local measurement workflow and acceptance signals for comparing OpenMUX idle power, CPU, memory, thread count, renderer/display-link activity, and process energy before and after runtime presentation optimizations.

### Modified Capabilities

- `ghostty-surface-hosting`: Add visibility/occlusion lifecycle behavior for bridge-owned hosted terminal surfaces while keeping libghostty-specific APIs behind the bridge.
- `workspace-render-reconciliation`: Require workspace rendering to derive stable visible/hidden surface state without rebuilding unrelated panes or leaking terminal-engine ownership into the shell.
- `terminal-scrollback-persistence`: Clarify that output from inactive but live sessions remains capturable/persistable even when presentation rendering is quiesced.

## Impact

- `Sources/OmuxTerminalBridge`: likely adds an OpenMUX-native surface visibility/occlusion method and maps it to libghostty inside `CGhosttyRuntime`.
- `Sources/OmuxAppShell`: derives visibility from active workspace/tab/pane/modal/window state and applies it during reconciliation and lifecycle transitions.
- `Sources/OmuxCore`: may need a small native model concept or helper for visible terminal pane identity if existing workspace helpers are insufficient.
- Tests: add bridge/runtime tests for occlusion calls, shell reconciliation tests for inactive workspaces/tabs, persistence tests for inactive-session output, and a documented manual or scripted power baseline flow.
- CLI/control plane/plugin APIs: no intended breaking change. Existing hooks, extension panes, and JSON-RPC terminal events should continue to observe live sessions.
- Keyboard/input: no intended behavior change. The change should preserve current focus semantics and avoid sending input to hidden or inactive surfaces.
- Architecture: reinforces the libghostty boundary by keeping upstream occlusion details inside the terminal bridge and exposing only OpenMUX-native visibility semantics to the shell.
