## 1. Bridge Text Snapshot Model

- [x] 1.1 Define or refine OpenMUX-native bounded terminal text result types for available text, truncation, limits, empty text, and unavailable reasons.
- [x] 1.2 Centralize runtime surface text capture in `OmuxTerminalBridge` so live snapshots, history, command output context, and persistence share one bounded-text path.
- [x] 1.3 Ensure all Ghostty text, point, selection, and buffer APIs remain confined to `OmuxTerminalBridge` implementation code.

## 2. Runtime Session Snapshots

- [x] 2.1 Update runtime-backed `TerminalSessionSnapshot` construction to populate bounded rendered text from hosted surface capture when available.
- [x] 2.2 Preserve explicit unavailable state when capture fails or is unsupported instead of fabricating transcript/current-input text.
- [x] 2.3 Keep empty-but-available terminal text distinguishable from unavailable terminal text.
- [x] 2.4 Preserve existing shell, working directory, size, pane, session, and runtime surface metadata in snapshots.

## 3. Automation and History Integration

- [x] 3.1 Update command completion enrichment to derive `outputContext` from the improved OpenMUX-native snapshot/history result.
- [x] 3.2 Ensure `terminal.commandFinished` hooks and control-plane events expose bounded output context when available and explicit unavailable context otherwise.
- [x] 3.3 Keep `omux history` and control-plane history responses compatible while using the shared bounded text source.

## 4. Persistence and Restore Semantics

- [x] 4.1 Update workspace persistence snapshot preparation to use the shared bounded runtime text capture semantics.
- [x] 4.2 Preserve restored historical scrollback when fresh runtime capture is unavailable and avoid fabricating new persisted output.
- [x] 4.3 Keep restored historical context distinguishable from fresh live runtime text.
- [x] 4.4 Ensure restore continues to launch fresh shell sessions and does not imply live PTY, process, SSH, or TUI restoration.

## 5. Validation

- [x] 5.1 Add bridge tests for successful bounded text capture, truncation, empty available text, and unavailable capture.
- [x] 5.2 Add app-shell/control-plane tests for command-finished output context populated from bounded snapshot/history text.
- [x] 5.3 Add persistence tests for bounded saved history, unavailable capture behavior, and restored historical context preservation.
- [x] 5.4 Add CLI/control-plane history tests confirming compatible response shape with richer runtime text and unavailable metadata.
- [x] 5.5 Run the existing relevant Swift test suite and OpenSpec validation for this change.
