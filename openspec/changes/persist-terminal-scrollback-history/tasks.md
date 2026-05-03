## 1. Model bounded scrollback snapshots

- [ ] 1.1 Add an OpenMUX-native bounded scrollback snapshot type to pane terminal/session state.
- [ ] 1.2 Add trimming behavior so persisted scrollback is bounded by conservative size or line limits.

## 2. Capture scrollback through the bridge

- [ ] 2.1 Extend terminal bridge/runtime protocols with an OpenMUX-native bounded scrollback snapshot request.
- [ ] 2.2 Implement Ghostty-backed text capture using `ghostty_surface_read_text` inside `OmuxTerminalBridge`.
- [ ] 2.3 Return an explicit unavailable result when the runtime cannot provide text.

## 3. Persist and restore historical context

- [ ] 3.1 Include bounded per-pane scrollback snapshots in workspace persistence.
- [ ] 3.2 Restore saved scrollback as historical context without claiming live process restoration.
- [ ] 3.3 Keep persisted scrollback out of hook payloads and control-plane events by default.

## 4. Validate behavior

- [ ] 4.1 Add tests for scrollback bounds, persistence, restore, and unavailable runtime behavior.
- [ ] 4.2 Run targeted terminal bridge and app-shell tests plus the repository test suite or closest existing target set.
