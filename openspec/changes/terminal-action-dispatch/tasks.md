## 1. Shared event contracts

- [x] 1.1 Add a structured OpenMUX-native payload value type in `OmuxCore` for terminal events, hooks, and control-plane event definitions
- [x] 1.2 Define OpenMUX-native terminal action/event types and supported first-wave event kinds without exposing Ghostty enums outside `OmuxTerminalBridge`
- [x] 1.3 Update `OmuxHooks` hook invocation contracts and tests to use structured payload values instead of string-only metadata for terminal automation events

## 2. Bridge event emission

- [x] 2.1 Extend `GhosttyTerminalBridge` with observer or sink registration for typed terminal action events keyed by pane and session
- [x] 2.2 Add bridge-owned translation types and helpers that classify Ghostty actions into supported, rejected, and deferred buckets
- [x] 2.3 Keep unsupported and app-shell Ghostty actions rejected by default and cover that behavior with bridge-level tests

## 3. CGhostty runtime decoding

- [x] 3.1 Replace the unconditional `action_cb` rejection in `CGhosttyRuntime` with decoding for the supported first-wave Ghostty actions
- [x] 3.2 Emit typed bridge events for `PWD`, title changes, URL open, desktop notification, bell, command-finished, progress, child-exited, and renderer-health actions
- [x] 3.3 Add runtime/bridge tests that prove supported Ghostty actions become OpenMUX-native events and Ghostty callback types do not leak outside the bridge module

## 4. App shell routing and automation fanout

- [x] 4.1 Add an `OmuxAppShell` terminal action coordinator that subscribes to bridge events and resolves workspace, tab, pane, and session context
- [x] 4.2 Update shell state and pane chrome for cwd, title, progress, child-exited, and renderer-health events
- [x] 4.3 Route URL open, desktop notification, bell, and command-finished outcomes through native macOS integrations and structured hook emissions
- [x] 4.4 Define OpenMUX-native control-plane terminal event names and payload shapes needed by the app-local publication path without adding a long-lived streaming transport

## 5. Documentation and verification

- [x] 5.1 Update architecture and development docs to describe terminal action dispatch, structured hook payloads, and the bridge-to-shell routing model
- [x] 5.2 Add or update tests across `OmuxCore`, `OmuxHooks`, `OmuxTerminalBridge`, and `OmuxAppShell` for typed payloads, event routing, and supported action outcomes
- [x] 5.3 Verify the fallback runtime path remains safe by emitting no unsupported fake terminal events when `libghostty` is unavailable
