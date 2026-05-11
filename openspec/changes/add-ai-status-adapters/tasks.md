## 1. Pane Status Contract

- [ ] 1.1 Audit `omux pane-status` and JSON-RPC pane-status behavior against the new control-plane requirements, including explicit target failures, state aliases, progress values, label/message/source fields, and local-only OpenMUX-native identifiers.
- [ ] 1.2 Add or update CLI/control-plane tests that cover adapter-style calls for `working`, `indeterminate`, `needs-input`, `idle`, `error`, and `clear`.
- [ ] 1.3 Update public docs for `omux pane-status` so hook and plugin authors can use it as the stable adapter reporting surface.

## 2. Adapter Framework And Examples

- [ ] 2.1 Define the external AI/tool status adapter contract in plugin documentation, including wrapper mode, observer mode, expected inputs, status outputs, and failure behavior.
- [ ] 2.2 Add a minimal adapter runner or example script structure for tool-specific adapters without introducing an in-process AI runtime.
- [ ] 2.3 Add a Codex-oriented adapter example that maps visible/process states to `working`, `needs-input`, `idle`, and `error` using public `omux pane-status` calls.
- [ ] 2.4 Document how future Claude, Copilot, and other tool adapters can be added independently using the same contract.

## 3. Hook And Plugin Integration

- [ ] 3.1 Ensure wrapper adapters launched inside OpenMUX panes can rely on `OMUX_PANE_ID` and `OMUX_SESSION_ID` for target selection.
- [ ] 3.2 Add hook/plugin examples showing adapter status updates from invocation payload IDs, terminal environment IDs, and discovery commands.
- [ ] 3.3 Verify adapter failures are isolated like other hook/plugin failures and do not block terminal sessions or later handlers.

## 4. Shell Rendering And Input Safety

- [ ] 4.1 Add tests proving adapter-reported pane status renders through the same tab/sidebar/pane chrome as terminal-native progress events.
- [ ] 4.2 Add regression coverage showing adapter status updates do not steal focus or alter terminal input routing.
- [ ] 4.3 Verify observer-style adapter documentation forbids input interception and preserves IME, dead-key, compose-key, Option, and right-Option behavior.

## 5. Validation

- [ ] 5.1 Run the relevant Swift tests for CLI, control-plane, hooks/plugins, and app-shell status rendering.
- [ ] 5.2 Run OpenSpec validation for `add-ai-status-adapters` and fix any spec or task formatting issues.
- [ ] 5.3 Smoke-test the Codex adapter example manually in an OpenMUX pane and confirm status changes appear without shifting tab/sidebar identity text.
