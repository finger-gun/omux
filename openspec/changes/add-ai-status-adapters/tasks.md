## 1. Pane Status Contract

- [x] 1.1 Audit `omux pane-status` and JSON-RPC pane-status behavior against the new control-plane requirements, including explicit target failures, state aliases, progress values, label/message/source fields, and local-only OpenMUX-native identifiers.
- [x] 1.2 Add or update CLI/control-plane tests that cover adapter-style calls for `working`, `indeterminate`, `needs-input`, `idle`, `error`, and `clear`.
- [x] 1.3 Update public docs for `omux pane-status` so hook and plugin authors can use it as the stable adapter reporting surface.

## 2. AI-Status Host And Adapter Examples

- [x] 2.1 Define the shared `ai-status` plugin host contract in plugin documentation, including wrapper mode, observer mode, expected inputs, host-owned normalization behavior, failure handling, and the explicit repo boundary between this repo and `finger-gun/omux-plugins`.
- [x] 2.2 Add or update the installable `ai-status` host package in `finger-gun/omux-plugins` (`/Users/lejahmie/projects/omux-plugins/`) with adapter-owned vendor modules without introducing an in-process AI runtime.
- [x] 2.3 Add a Codex-oriented adapter example as the first worked adapter, mapping visible/process states to `working`, `needs-input`, `idle`, and `error` using public `omux pane-status` calls.
- [x] 2.4 Document how Gemini, Claude, Copilot, and future tool adapters plug into the same `ai-status` host without requiring one plugin per vendor.
- [x] 2.5 Ensure the shared host dedupes noisy observer signals and synthesizes `clear` only from meaningful state transitions or stale/session-end rules.

## 3. Hook And Plugin Integration

- [x] 3.1 Ensure wrapper adapters launched inside OpenMUX panes can rely on `OMUX_PANE_ID` and `OMUX_SESSION_ID` for target selection.
- [x] 3.2 Add hook/plugin examples showing adapter status updates from invocation payload IDs, terminal environment IDs, and discovery commands, with OpenMUX-side examples in this repo and installable plugin examples in `finger-gun/omux-plugins`.
- [x] 3.3 Verify adapter failures are isolated like other hook/plugin failures and do not block terminal sessions or later handlers.

## 4. Shell Rendering And Input Safety

- [x] 4.1 Add tests proving adapter-reported pane status renders through the same tab/sidebar/pane chrome as terminal-native progress events.
- [x] 4.2 Add regression coverage showing adapter status updates do not steal focus or alter terminal input routing.
- [x] 4.3 Verify observer-style adapter documentation forbids input interception and preserves IME, dead-key, compose-key, Option, and right-Option behavior.

## 5. Validation

- [x] 5.1 Run the relevant Swift tests for CLI, control-plane, hooks/plugins, and app-shell status rendering.
- [x] 5.2 Run OpenSpec validation for `add-ai-status-adapters` and fix any spec or task formatting issues.
- [ ] 5.3 Smoke-test the Codex adapter example manually in an OpenMUX pane and confirm status changes appear without shifting tab/sidebar identity text.
