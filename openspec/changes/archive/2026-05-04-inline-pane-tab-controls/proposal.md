## Why

Pane-local tab creation currently lives as a separate pane-level `+` control, while existing local tabs are rendered elsewhere. This makes the tab strip feel less direct than a terminal-first workspace should: the primary action for adding another terminal in the same pane stack should live exactly where the user is already scanning pane-local tabs.

Close affordances are also too indirect. Users should be able to close a local pane tab from the tab itself without leaving the pane-tab strip or relying on menus, shortcuts, or automation.

## Goals

- Place the pane-local new-tab affordance immediately after the last local pane tab in each pane stack.
- Add an inline close affordance to each pane-local tab.
- Preserve the existing shared pane-stack actions so native UI, shortcuts, and `omux` continue to use the same model/control-plane behavior.
- Keep the UI native, lightweight, and terminal-first, with no browser-style tab subsystem or additional background service.

## Non-goals

- Do not change top-level workspace tabs or workspace switching behavior.
- Do not introduce draggable tab reordering, detachable tabs, or cross-pane tab movement.
- Do not change CLI or JSON-RPC contracts for pane-tab create/close actions.
- Do not move pane-tab ownership into `libghostty`; the shell remains responsible for pane-stack chrome.

## What Changes

- Move the pane-stack `+` control from separate pane chrome to the inline local tab strip, positioned immediately after the last local pane tab.
- Add an `x` close control on each pane-local tab that invokes the same close action as existing pane-tab close behavior.
- Keep close controls disabled or absent when a pane stack has only one local tab, matching existing single-tab close restrictions.
- Preserve existing keyboard and CLI behavior for creating and closing pane-local tabs.
- Ensure the inline controls do not intercept terminal keyboard input, IME composition, Option/right-Option input, or terminal pointer selection outside the pane-tab chrome.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `pane-tab-stacks`: Pane-local tab stacks gain explicit inline create and close affordance requirements.
- `pane-chrome-identity`: Pane chrome requirements change so local tab controls are part of the tab strip rather than a separate redundant chrome row/action.
- `macos-app-shell`: Native shell behavior changes to render and route inline pane-tab controls through AppKit-owned shell chrome while preserving the terminal bridge boundary.

## Impact

- Affected code: pane-stack chrome rendering and hit targets in `OmuxAppShell`, pane-tab close/create UI wiring, app-shell tests.
- APIs: no intended changes to CLI, JSON-RPC, hooks, plugin APIs, or persistence schema.
- Dependencies: no new runtime dependencies or background services.
- Keyboard/input: no new global shortcuts; pointer interaction is limited to native pane-tab chrome and must not affect terminal-owned keyboard paths.
- Terminal bridge: no `libghostty` bridge changes; pane-tab chrome remains OpenMUX-native shell UI around terminal surfaces.
