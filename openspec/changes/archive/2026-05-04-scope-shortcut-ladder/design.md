## Context

OpenMUX now uses `Cmd+T` and `Cmd+W` for pane-local tab create/close. That is correct for the smallest structural scope, but it displaced the previous `Cmd+W` workspace delete shortcut and leaves pane removal less discoverable than the existing pane split shortcuts.

Current state:
- Pane tab: `Cmd+T` creates, `Cmd+W` closes.
- Pane split: `Cmd+D` splits right, `Cmd+Shift+D` splits down.
- Pane remove: `Cmd+Shift+Backspace`.
- Workspace create: `Cmd+N`.
- Workspace delete: menu action only, no shortcut.
- CLI has `omux open`, `omux split`, `omux pane-tab`, and `omux pane-tab-close`, but lacks explicit workspace close and pane remove commands.

## Goals / Non-Goals

**Goals:**
- Add predictable create/delete pairs where creation is not already covered:
  - pane tab: `Cmd+T` / `Cmd+W`
  - pane split: `Cmd+D` / `Cmd+Shift+D`
  - pane remove: `Cmd+Shift+W`
  - workspace: `Cmd+N` / `Cmd+Shift+N`
- Preserve existing pane split shortcuts.
- Add missing CLI/control-plane parity for workspace close and pane remove.
- Keep all shortcuts explicit in the input allowlist.

**Non-Goals:**
- Do not remove or remap existing working shortcuts.
- Do not bind Option-based shortcuts.
- Do not add keybinding customization.
- Do not change pane-tab command names that already exist.

## Decisions

### Decision: Keep pane split shortcuts and improve pane removal

OpenMUX SHALL keep `Cmd+D` for split right and `Cmd+Shift+D` for split down. `Cmd+Shift+W` SHALL remove the active pane. Existing `Cmd+Shift+Backspace` SHALL no longer be claimed as a pane-remove shortcut.

**Rationale:** The existing pane creation shortcuts already cover both split directions. Adding `Cmd+Shift+T` would duplicate pane creation without adding capability, while `Cmd+Shift+W` makes pane removal more mnemonic and lets modified Backspace remain terminal-owned.

**Alternative considered:** Add `Cmd+Shift+T` as another pane-add alias. The user rejected this because pane creation is already covered by `Cmd+D` and `Cmd+Shift+D`.

### Decision: Use `Cmd+Shift+N` for workspace close/delete

Workspace create remains `Cmd+N`; workspace close/delete gets `Cmd+Shift+N`.

**Rationale:** This mirrors the pane-tab and pane create/delete pair by making Shift indicate the larger/destructive counterpart at the workspace scope, while avoiding Option.

**Alternative considered:** Use `Cmd+Ctrl+W` for workspace close. It is plausible but less mnemonic and would make workspace actions diverge from the create/delete pairing.

### Decision: Add explicit control-plane methods for destructive structural actions

Add `workspace.close` and `pane.remove` rather than overloading unrelated methods. The CLI commands route through these methods.

**Rationale:** Closing a workspace and removing a pane are first-class OpenMUX structure mutations. Explicit methods are easier to inspect and safer for automation than hidden UI-only actions.

**Alternative considered:** Have the CLI synthesize UI shortcuts or reuse restore/open semantics. That would blur the local RPC boundary and make automation less predictable.

### Decision: CLI commands are additive and targetable

Add:
- `omux workspace-close [workspace-id]`
- `omux pane-remove [--session <id>|--pane <id>|--tab <id>|--workspace <id>|--focused]`

Keep existing commands:
- `omux open [path]`
- `omux split ...`
- `omux pane-tab`
- `omux pane-tab-close [pane-id]`

**Rationale:** The missing pieces are close/delete operations at workspace and pane scope. Existing creation commands already cover workspace/pane/pane-tab creation.

**Alternative considered:** Add `workspace-new` and `pane-add` aliases immediately. That may be useful later, but it is not required for parity because `open` and `split` already exist.

## Risks / Trade-offs

- **Risk:** `Cmd+Shift+N` may conflict with a user expectation from Finder. -> **Mitigation:** In OpenMUX it is app-scoped, explicit, and paired with `Cmd+N` workspace creation.
- **Risk:** More shortcuts could accidentally claim terminal input. -> **Mitigation:** Add only exact Command/Command+Shift allowlist entries and preserve unknown Command/Option behavior.
- **Risk:** CLI destructive commands could close the wrong target. -> **Mitigation:** Use explicit optional IDs/targets, default to active only when omitted, and return structured failures for invalid targets.
- **Risk:** Existing shortcut tests may assume a narrower allowlist. -> **Mitigation:** Update tests to prove both new shortcuts and unknown/Option chords behave correctly.
