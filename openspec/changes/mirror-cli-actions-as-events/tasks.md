## 1. Generic control-plane event model

- [ ] 1.1 Replace the terminal-only control-plane event type with a generic OpenMUX event envelope that supports optional workspace, tab, pane, and session identifiers
- [ ] 1.2 Update the local control-plane streaming service and `omux events` client path to publish and decode the generic event envelope without regressing existing `terminal.*` events

## 2. Shared action event publication

- [ ] 2.1 Add a `WorkspaceController` publishing helper so shared actions can emit OpenMUX-native control-plane events next to existing state updates and hook emission
- [ ] 2.2 Emit first-wave parity events for `open`, `tab`, `split`, `pane-tab`, `pane-tab-focus`, `pane-tab-close`, `focus`, `run`, `notify`, and `restore` only when those actions succeed
- [ ] 2.3 Ensure each action event carries sparse, action-appropriate payloads and does not invent pane/session context for app-level events

## 3. Terminal event migration

- [ ] 3.1 Adapt terminal runtime publication so the existing terminal-action coordinator publishes `terminal.*` events through the new generic event envelope
- [ ] 3.2 Preserve the `libghostty` bridge boundary by keeping Ghostty-specific translation inside `OmuxTerminalBridge` while the app shell publishes only OpenMUX-native event names and payloads

## 4. Verification

- [ ] 4.1 Add or update `OmuxControlPlane` and `OmuxCLI` tests for mixed action and terminal event streaming over the local JSON-RPC subscription surface
- [ ] 4.2 Add or update `OmuxAppShell` tests proving shared actions emit parity events for both successful and rejected controller actions
- [ ] 4.3 Verify command injection, focus changes, and pane-tab actions still target live sessions correctly and do not alter keyboard/input behavior

## 5. Documentation

- [ ] 5.1 Update developer-facing docs to describe `omux events` as a generic local event stream and document the first-wave action event names
