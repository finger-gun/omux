## Context

The sidebar already renders workspace rows followed by terminal metadata rows for each pane tab in each workspace. The row action currently calls pane focus through an active-workspace path, so rows that represent terminals in inactive workspaces can be visible but not directly activated.

The app menu currently uses one View menu for workspace lifecycle, workspace navigation, pane layout, pane-tab navigation, and visual chrome toggles. That made sense while the shell had only a few actions, but the menu now mixes OpenMUX model operations with view/chrome operations.

## Goals / Non-Goals

**Goals:**

- Make every visible terminal metadata row in the sidebar a direct focus target for its pane tab.
- Reuse shared workspace/session focus semantics so sidebar clicks update active workspace, focused tab, focused pane stack, focused pane tab, events, persistence, and terminal first responder consistently.
- Split the menu into Workspace, Pane, and View responsibilities while preserving existing keybindings and menu validation.
- Keep the change AppKit-shell owned and independent from libghostty.

**Non-goals:**

- Add new CLI or JSON-RPC commands.
- Change terminal input handling, key encoding, or Ghostty focus APIs.
- Add sidebar drag/reorder for pane tabs.
- Add command interception, shell integration, browser/webview UI, or a background service.

## Decisions

### Decision: make pane focus cross-workspace

The shared pane-focus path should locate a pane by ID across all workspaces. When a pane is found, OpenMUX updates the active workspace, focused top-level tab, focused pane stack, and active pane tab using existing model methods. This makes sidebar terminal rows and `pane-tab-focus` semantics match the visible object the user selected.

Alternative considered: have the sidebar first restore the workspace and then call active-workspace pane focus. This duplicates model lookup in UI code and risks event/persistence inconsistencies.

### Decision: keep sidebar row clicks model-level

Sidebar row clicks call the shared controller focus operation, not bridge/runtime focus APIs. The window refresh remains driven by `WorkspaceController.onChange`, which already updates shell chrome and restores first responder to the focused hosted pane view.

### Decision: split model actions out of View

The menu organization becomes:

- **Workspace**: workspace create/rename/delete, previous workspace, move workspace, direct workspace jumps.
- **Pane**: split/remove pane, pane-tab create/close/next/previous, pane next/previous.
- **View**: visual shell/chrome toggles such as the workspace column.

Shortcut assignment still comes from the keybinding registry, so the split is organizational rather than behavioral.

## Risks / Trade-offs

- Moving menu items changes where users find actions. This is mitigated by clearer top-level concepts and preserved shortcuts.
- Cross-workspace pane focus must preserve previous-workspace recall. Activating a pane in another workspace should record the prior active workspace through the existing active workspace setter.
- Direct sidebar focus should not leak terminal-engine details; all operations remain in `OmuxAppShell` and `OmuxCore` models.

## Test Strategy

- Add controller coverage that focusing a pane tab in an inactive workspace activates that workspace and emits focus events.
- Add AppKit sidebar coverage that clicking a terminal metadata row focuses the represented pane tab.
- Update menu tests to assert Workspace, Pane, and View menu placement while preserving shortcut rebinding and unbinding behavior.
