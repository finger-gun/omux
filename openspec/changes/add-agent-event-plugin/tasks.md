## 1. Terminal Progress Model

- [x] 1.1 Keep Ghostty/OSC progress mapped to OpenMUX-native pane progress state.
- [x] 1.2 Treat removed/done progress as brief idle state before clearing.
- [x] 1.3 Preserve non-persistence for transient progress/status state.

## 2. Pane Chrome Rendering

- [x] 2.1 Render status orbs in workspace/sidebar pane rows before semantic icons.
- [x] 2.2 Render status orbs in pane tabs before the tab name/icon.
- [x] 2.3 Map working/indeterminate to pulsing orb, error to red, and idle to brief blue.
- [x] 2.4 Respect reduced-motion settings for pulse animation.
- [x] 2.5 Avoid replacing pane titles, semantic icons, or cwd identity with status text.

## 3. Hooks, Plugins, and CLI

- [x] 3.1 Add provider-neutral `pane.status` JSON-RPC request handling.
- [x] 3.2 Add `omux pane-status` with `--session`, `--pane`, `--tab`, `--workspace`, and `--focused` selectors.
- [x] 3.3 Publish `pane.statusChanged` events with normalized state, value, label, message, and source fields.
- [x] 3.4 Document hook/plugin usage and add a copy-pasteable hook example.

## 4. Validation

- [x] 4.1 Add CLI coverage for pane-status request parsing and payload shape.
- [x] 4.2 Add app-shell coverage for terminal progress orbs and brief idle clearing.
- [x] 4.3 Add control-plane coverage for pane status mutation and event payloads.
- [x] 4.4 Run relevant Swift tests and shell syntax checks.
