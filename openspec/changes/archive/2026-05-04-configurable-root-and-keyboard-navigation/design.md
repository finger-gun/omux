## Context

OpenMUX already has the right primitives for this change: a strict OpenMUX-owned TOML config loader, a shared workspace controller, a local JSON-RPC control plane, CLI commands layered on that control plane, and an allowlisted input pipeline. The current gaps are mostly wiring and contract clarity:

- first-launch and no-path workspace creation fall back to the app process working directory, which can be `/`;
- `omux open` requires a path even though the control-plane operation can already tolerate missing path data;
- pane-local tab create/close/focus exists, but keyboard and CLI navigation parity is incomplete;
- pane focus can target explicit IDs, but there is no shared next/previous navigation operation.

The implementation should stay AppKit-first and OpenMUX-native. No libghostty types are needed for path resolution or navigation order.

## Goals / Non-Goals

**Goals:**

- Add `[workspace] default_root_path` as a documented OpenMUX config setting with a home-directory default.
- Normalize configured and explicit workspace paths consistently, including `~` expansion.
- Make app first launch, sidebar/menu workspace creation, control-plane workspace open, and `omux open` without a path use the configured default root.
- Add shared next/previous actions for pane-local tabs and panes.
- Wire native shortcuts and CLI commands to those shared actions.
- Keep shortcut interception exact and layout-safe for international keyboard input.

**Non-Goals:**

- No project picker, recent-project database, file indexing, or background service.
- No changes to terminal-engine configuration or libghostty integration.
- No configurable keymap system in this change; shortcuts remain hardcoded explicit OpenMUX commands.
- No change to existing workspace number shortcuts.

## Decisions

### Decision: Model default root as `[workspace] default_root_path`

Use a new `OmuxConfigWorkspace` section with `defaultRootPath`, exposed in TOML as:

```toml
[workspace]
default_root_path = "~"
```

Rationale: existing user-facing config keys use snake_case and OpenMUX owns workspace behavior, so this belongs under a new `[workspace]` table rather than `[terminal]` or `[ghostty]`.

Alternative considered: `defaultRootPath` at top level. Rejected because it diverges from current TOML style and mixes workspace behavior into the root schema.

### Decision: Resolve no-path opens through a single default-root provider

The app shell should receive the prepared/effective config at launch and pass the default root to the workspace controller or a small resolver. The resolver expands `~`, standardizes paths, and falls back to the user's home directory only when the setting is absent. Invalid configured paths should produce config diagnostics rather than silently degrading to `/`.

Alternative considered: let each caller choose its own fallback. Rejected because it recreates current drift between app launch, UI, CLI, and RPC behavior.

### Decision: Keep explicit path opens explicit

`omux open <path>` and RPC `workspace.open` with `path` continue to open that path. Only missing or omitted path data uses the configured default root.

Alternative considered: always rewrite relative or explicit paths against the configured default. Rejected because a terminal CLI should respect the caller's explicit input and current shell expectations.

### Decision: Add shared navigation operations before UI bindings

Add controller/control-plane methods for:

- focus next pane-local tab;
- focus previous pane-local tab;
- focus next pane in visible layout order;
- focus previous pane in visible layout order.

Native shortcuts and CLI commands should call these methods instead of duplicating order logic.

Alternative considered: implement shortcuts directly in `OpenMUXAppDelegate`. Rejected because hooks, CLI, and tests need the same behavior.

### Decision: Use visible split-tree order for pane cycling

Pane cycling uses the current workspace's focused top-level tab and the split-tree's visible pane order. Pane-local tabs inside each stack are represented by the stack's active pane for inter-pane cycling; `Ctrl+Tab` handles cycling within the focused stack.

Alternative considered: most-recently-focused order. Rejected for now because visible order is deterministic, inspectable, and easier to test.

### Decision: Intercept only exact navigation chords

The input classifier should treat `Cmd+T`, `Cmd+W`, `Ctrl+Tab`, and `Ctrl+Shift+Tab` as OpenMUX shortcuts in addition to existing workspace/split/sidebar shortcuts. It should not treat arbitrary Control chords as shortcuts.

Alternative considered: route all Control+Tab-like events through terminal input and rely on menus. Rejected because focused runtime panes need to hand known OpenMUX shortcuts back to AppKit instead of consuming them.

## Risks / Trade-offs

- **Invalid configured root blocks useful startup** -> Emit a config diagnostic and use the built-in home default only when the user setting is absent or the config falls back to defaults because of validation errors.
- **`Cmd+W` currently conflicts with workspace delete** -> Reassign or remove the workspace-delete key equivalent so `Cmd+W` consistently closes the focused pane-local tab.
- **Tab key event normalization can vary by AppKit text input path** -> Cover raw normalized `\t` / keyCode cases in input tests and native menu key equivalents.
- **Pane visible order could surprise users in complex nested layouts** -> Use the existing split-tree traversal order and document it as visible layout order; keep previous/next CLI commands for deterministic scripting.
- **Adding `[workspace]` table changes strict config validation** -> Update allowed tables and tests so unknown-key behavior remains strict outside the new documented keys.
