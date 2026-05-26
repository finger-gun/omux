## 1. Publication Seam Readiness

- [x] 1.1 Confirm the controller publication seam from `refactor-workspace-controller-structure` exists or extract the minimum equivalent boundary needed for Phase 1 hook/event wiring.
- [x] 1.2 Add or extend shared publication helpers for the new action-event names and hook names without widening the terminal bridge boundary.

## 2. Control-Plane Event Parity

- [x] 2.1 Emit success-shaped control-plane events for workspace close and pane remove outcomes through the controller-owned publication path.
- [x] 2.2 Emit success-shaped control-plane events for pane alias set/clear outcomes through the shared alias action path.
- [x] 2.3 Emit `config.reloaded` for successful config apply/reload completion from both explicit command and watched reload sources.
- [x] 2.4 Extend extension-pane event coverage so close events are streamed alongside create/update.

## 3. Hook Parity

- [x] 3.1 Emit `workspace-restored` for successful workspace restore outcomes.
- [x] 3.2 Emit `extension-pane-created`, `extension-pane-updated`, and `extension-pane-closed` for successful extension-pane lifecycle outcomes.
- [x] 3.3 Emit `pane-status-updated` for successful pane-status set/change/clear outcomes.
- [x] 3.4 Emit `config-reloaded` for successful config apply/reload completion from both explicit command and watched reload sources.

## 4. Documentation and Validation

- [x] 4.1 Update `docs/open-by-design.md` to mark the covered Phase 1 rows and leave untouched gaps explicit.
- [x] 4.2 Update `docs/hooks.md` and any affected control-plane/development docs with the new hook names, payloads, and event coverage.
- [x] 4.3 Add or update app-shell, control-plane, and CLI tests that verify new hook/event emissions occur only for success-shaped outcomes and preserve existing payload compatibility.
- [x] 4.4 Run the relevant AppShell/CLI/ControlPlane test suites and confirm the new observability wiring does not change keyboard/input behavior or terminal action semantics.
