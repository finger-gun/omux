## Context

`docs/open-by-design.md` already defines the desired automation contract for user-visible transitions, and the codebase already has most of the underlying actions. The remaining gaps in this first wave are mostly parity gaps rather than new product behavior: some transitions already have a hook but no event, some have an event but no hook, and config reload is still treated primarily as an imperative CLI action instead of a generally observable state transition.

This work touches multiple capability contracts and the same app-shell publication paths that the `refactor-workspace-controller-structure` change is trying to isolate. The implementation therefore needs to improve surface coverage without reintroducing more scattered inline emission logic in `WorkspaceController`.

## Goals / Non-Goals

**Goals:**
- Add the missing first-wave hook and control-plane event coverage for the selected transitions in `docs/open-by-design.md`.
- Reuse one controller-owned publication seam for new hook/event emission wherever possible.
- Keep names, payloads, and identifiers aligned with existing OpenMUX-native hook and control-plane conventions.
- Treat config reload as an observable config-application outcome, not only as an imperative CLI request.

**Non-Goals:**
- Closing all remaining gaps in `docs/open-by-design.md`.
- Adding new CLI verbs for rows that currently lack them.
- Changing terminal input routing, keyboard semantics, or libghostty-facing APIs.
- Introducing approval/rewriting hooks, event replay, or any command-input behavior on the event stream.

## Decisions

### 1) Phase 1 stays strictly on existing transitions
This wave only covers transitions that already exist in the product and already have at least one public surface or well-defined shared action path.

- **Why:** this keeps the change small, defensible, and easy to validate against the coverage table.
- **Alternative rejected:** mixing in workspace focus, resize, reorder, or other blank-cell features. That would turn parity work into broader product design.

### 2) New observability attaches at controller-owned outcome points
Hooks and events should be emitted only where controller-owned state transitions have actually completed, and should reuse the publication seam extracted by the controller refactor instead of adding more ad hoc emission paths.

- **Why:** the same transition may be invoked from CLI, menus, palette, or plugin flows. Controller-owned outcomes preserve parity and keep the event stream observational.
- **Alternative rejected:** emitting from the CLI or JSON-RPC service layer. That would miss app-shell initiated actions and create drift across entry points.

### 3) Action events remain success-shaped and sparse
New control-plane events should follow the existing action-event model: emit only for successful outcomes, include only the context IDs that genuinely exist, and keep payloads minimal and OpenMUX-native.

Examples:
- `workspace.closed` carries workspace identity and root path.
- `pane.removed` carries workspace/tab/pane/session context when a pane is actually removed.
- `pane.aliasSet` and `pane.aliasCleared` carry pane identity plus alias payload when relevant.
- `config.reloaded` carries source and apply status for successful reload/apply completion.

- **Why:** this preserves consistency with the existing `control-plane-action-events` model and avoids turning the event stream into an intent log.
- **Alternative rejected:** emitting attempted actions or stuffing unrelated diagnostic detail into every payload.

### 4) Hook names follow existing OpenMUX naming conventions
This wave should extend hooks using the same hyphenated OpenMUX naming already present in `docs/hooks.md` and `WorkspaceController`, rather than inventing a second naming scheme.

Planned hook family:
- `workspace-restored`
- `extension-pane-created`
- `extension-pane-updated`
- `extension-pane-closed`
- `pane-status-updated`
- `config-reloaded`

- **Why:** this keeps hook discovery predictable and compatible with the directory-based user hook layout.
- **Alternative rejected:** deriving hook names mechanically from event names or overloading existing hooks with multi-purpose payloads.

### 5) Config reload observability covers successful apply completion regardless of trigger
Config reload hooks/events should be emitted when OpenMUX successfully completes a config apply/reload pass, whether triggered by `omux config reload` or file/theme watching. The payload should include an OpenMUX-owned source field and whether the effective configuration changed.

- **Why:** OpenMUX already treats watched config changes and explicit reload as the same apply path. External automation should observe the resulting state change, not just one trigger mechanism.
- **Alternative rejected:** limiting observability to the CLI verb only. That would leave file-watcher-driven applies invisible despite using the same config behavior.

## Risks / Trade-offs

- **[Risk] The coverage table drifts from implementation again** → **Mitigation:** require documentation updates in the same change for `docs/open-by-design.md` and `docs/hooks.md`.
- **[Risk] Refactor and parity work step on the same controller code** → **Mitigation:** treat the publication seam from the refactor as a prerequisite attachment point and avoid spreading new direct emission calls.
- **[Risk] Config reload success semantics are ambiguous when nothing changed** → **Mitigation:** distinguish successful reload completion from “effective config changed” using an explicit payload field instead of separate event names.
- **[Risk] Extension-pane close overlaps with pane removal semantics** → **Mitigation:** keep pane removal and extension-pane close as distinct observations, because one describes shell layout removal and the other describes the extension-pane lifecycle contract.

## Migration Plan

1. Land or build against the extracted publication seam from `refactor-workspace-controller-structure`.
2. Add delta specs for the affected capability contracts.
3. Wire the missing hook/event emission at controller-owned transition completion points.
4. Update `docs/open-by-design.md` and `docs/hooks.md` to match the implemented contract.
5. Validate with focused control-plane, app-shell, and CLI tests that existing payloads remain compatible and new emissions occur only on success-shaped outcomes.

Rollback remains straightforward while unreleased: remove the added emission wiring, revert the new hook/event names, and restore the prior docs/spec state.

## Open Questions

- Should `config-reloaded` expose full structured diagnostics on success, or only a bounded summary plus source/applied fields?
- For extension-pane close, should the hook/event payload carry only `pluginID`, or should it also include `contentKind` and presentation metadata for symmetry with create/update?
