## Why

OpenMUX already exposes many core workspace and pane actions, but several common user-visible transitions still stop short of the full "open by design" contract described in `docs/open-by-design.md`. That leaves automation uneven: some actions can be triggered and observed cleanly, while others require polling, UI scraping, or have no reaction surface at all.

This change closes a narrow first wave of parity gaps on transitions that already exist in the product and already have at least one public surface. It improves hackability without expanding the terminal bridge boundary, adding background services, or introducing new workflow-specific product behavior.

## Goals

- Close selected high-value hook and control-plane event gaps for already-supported transitions.
- Keep all payloads and identifiers OpenMUX-native and compatible with the documented hook/event model.
- Improve external automation for workspace, pane, extension-pane, pane-status, and config-reload flows without broadening CLI scope beyond what Phase 1 needs.
- Align implementation work with the `docs/open-by-design.md` coverage table so the documented openness contract stays current.

## Non-goals

- No attempt to close every blank cell in `docs/open-by-design.md`.
- No second-wave decisions about ambiguous CLI verbs such as title-setting, bell, or URL-opening.
- No new browser-heavy, daemon-style, or vendor-specific automation surface.
- No changes to terminal keyboard/input behavior or expansion of the `libghostty` bridge boundary.

## What Changes

- Add control-plane action events for `workspace.close`, `pane.remove`, and pane alias set/clear outcomes.
- Add hook observability for workspace restore, extension-pane create/update/close, and pane-status updates.
- Add config-reload completion observability through both a hook and a control-plane event while preserving the existing `omux config reload` command.
- Extend extension-pane lifecycle event coverage so close events are streamed alongside create/update events.
- Update `docs/open-by-design.md` and affected public docs to reflect the new coverage.
- Explicitly leave unrelated blank coverage cells unchanged in this wave.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `control-plane-action-events`: expand the first parity wave with additional success-shaped action events for existing workspace, pane, alias, and config-reload transitions.
- `hooks-foundation`: expose additional stable hooks for restore, extension-pane lifecycle, pane-status updates, and config-reload completion.
- `config-system`: make config reload observable as a completed apply/reload outcome through public hook and event surfaces.
- `extension-content-panes`: make extension-pane lifecycle transitions hook-observable and include close coverage alongside existing create/update observability.
- `omux-control-plane`: extend documented event-stream coverage for extension-pane lifecycle and config/pane-status related observability.

## Impact

- Affected code will primarily live under `Sources/OmuxAppShell/WorkspaceController.swift`, publication helpers extracted by the controller refactor, `Sources/OmuxControlPlane/*`, and `Sources/OmuxCLI/OmuxCLI.swift`.
- Public automation surfaces change: hook names/payloads, `omux events` output, and related docs become more complete for selected transitions.
- No intended breaking change to existing CLI verbs, plugin command contracts, or terminal bridge types.
- Keyboard/input correctness is not directly changed by this wave, but tests must confirm the new observability wiring does not alter terminal input routing or timing.
