## Context

OpenMUX now receives terminal-owned title and working-directory updates through the dispatch pipeline, but the shell still presents workspaces and terminals using early placeholder naming and a flat sidebar. Workspaces inherit their initial names from the root path, workspace management actions largely live in top-level menus, and pane chrome can show a duplicated cwd/status row that competes with the pane title. The user wants the shell to feel more like a workspace navigator: generated workspace names, local context menus, and sidebar metadata that exposes where each terminal actually is.

This change is cross-cutting across `OmuxCore` model types, `OmuxAppShell` view composition, and shell-side metadata derivation, but it does not require any new `libghostty` bridge surface. The bridge already provides the terminal cwd/title events needed for the app shell to derive richer navigation state.

## Goals / Non-Goals

**Goals:**
- Introduce explicit workspace name semantics so OpenMUX can distinguish generated labels from user-defined labels.
- Add AppKit-native context menus for workspace rows and pane-tab surfaces without changing existing keyboard shortcuts or terminal input handling.
- Extend the sidebar from a flat workspace list into a lightweight terminal index that surfaces repo/branch/path metadata derived from terminal state.
- Clarify pane chrome so identity and transient terminal status are presented in distinct places with less duplication.
- Keep repo and branch resolution in OpenMUX-owned shell code with cheap, on-demand git queries and caching, not in the terminal bridge or a background daemon.

**Non-Goals:**
- Building a full source-control subsystem, file tree, or browser-like navigation panel.
- Introducing a polling service that continuously indexes repositories.
- Exposing raw split-tree internals directly in the sidebar if a terminal-oriented summary is sufficient.
- Altering terminal key handling, Option semantics, IME behavior, or other keyboard correctness surfaces beyond standard AppKit menu integration.

## Decisions

### 1. Separate generated workspace names from custom workspace names

`Workspace.name` is currently a single stored string, which makes "remove custom name" ambiguous. The model should instead represent a stable generated label plus an optional override, with display name derived from override-or-default. This keeps numbering predictable (`Workspace 1`, `Workspace 2`, ...) and makes reset-to-default a first-class operation rather than string heuristics.

**Alternatives considered**
- Keep a single stored `name` and guess whether it is custom. Rejected because collisions and rename cycles make intent ambiguous.
- Continue deriving defaults from `rootPath`. Rejected because the user explicitly wants workspace labels to represent shell containers, not repeated path basenames.

### 2. Model sidebar children as terminal entries, not every internal node

The shell model contains workspaces, workspace tabs, pane stacks, and pane tabs. The sidebar should expose the terminals users navigate to, not dump every internal layout node. Each workspace row can own a list of terminal-oriented child items sourced from the panes that currently exist inside that workspace.

Each child row should prefer:
1. repository name or branch context when available,
2. branch name,
3. abbreviated path,
4. subtle typography so the workspace row remains primary.

**Alternatives considered**
- Keep the sidebar flat and squeeze metadata into a single workspace subtitle. Rejected because it loses per-terminal visibility and will not scale once multiple terminals diverge in cwd or branch.
- Mirror split/tree structure exactly. Rejected because it exposes implementation detail instead of workflow-relevant navigation.

### 3. Resolve git metadata on demand from pane cwd

Git metadata should come from OpenMUX-owned shell services that inspect a pane's reported cwd and derive repository root, repository name, branch name, or detached state as needed. Queries should be triggered on meaningful state changes such as workspace creation, workspace activation, or cwd updates, then cached per repository path to avoid repeated shell-outs during render.

This keeps the terminal bridge narrow and avoids a persistent watcher or daemon. If git metadata is unavailable, the sidebar should gracefully fall back to path-only metadata.

**Alternatives considered**
- Put git detection in `libghostty` or dispatch translation. Rejected because git state is not terminal-engine behavior.
- Poll continuously in the background. Rejected on performance and simplicity grounds.

### 4. Use native context menus with action providers shared across surfaces

Workspace rows and pane-tab surfaces should both present AppKit context menus backed by OpenMUX-owned action providers. The menu vocabulary can overlap, but semantics remain local to the surface:
- workspace rows operate on workspace ordering in the sidebar,
- pane-tab surfaces operate on pane-tab ordering inside a pane stack.

Shared action-building logic avoids duplicated enablement rules while keeping view code small.

**Alternatives considered**
- Add more top-level menu items only. Rejected because the requested workflow is localized, contextual action.
- Use custom popovers instead of NSMenu. Rejected because native context menus are simpler and preserve expected macOS interaction.

### 5. Reserve pane status text for transient state

The pane title/pill already communicates terminal identity well once dispatch-driven names are working. The secondary status row should only render when it adds transient state not already visible elsewhere, such as progress, exit status, or renderer health. Reported cwd by itself should not keep a persistent status row alive.

**Alternatives considered**
- Keep the current cwd-based status row and add sidebar metadata as well. Rejected because it duplicates identity in two places and harms scanability.

## Risks / Trade-offs

- **[Risk] Sidebar density grows too quickly with many terminals** → Mitigation: keep workspace rows primary, use subtle child-row typography, and default expansion to active or relevant workspaces rather than forcing every workspace open.
- **[Risk] Git queries add visible latency during cwd changes** → Mitigation: resolve on demand, cache by repo root, and fall back to path-only metadata when git is slow or unavailable.
- **[Risk] Name model changes affect RPC/control-plane consumers** → Mitigation: keep exported display name stable while making custom/default provenance additive in internal models first.
- **[Risk] Context menus interfere with selection or focus** → Mitigation: use standard AppKit menu invocation paths and preserve current left-click focus behavior and keyboard shortcuts unchanged.
- **[Risk] Sidebar terminal rows expose too much implementation detail** → Mitigation: keep the model terminal-oriented and avoid split-tree terminology in visible UI.

## Migration Plan

1. Introduce additive workspace naming model changes while preserving current display-name accessors.
2. Add shell-side git metadata derivation and caching with no bridge changes.
3. Refactor sidebar rendering to support workspace rows plus terminal metadata children.
4. Add shared context-menu action builders and wire them to workspace rows and pane-tab surfaces.
5. Simplify pane status-row rendering so cwd-only duplication is removed while transient states remain visible.
6. Update tests for workspace naming, sidebar rendering, git metadata fallbacks, menu enablement, and pane chrome behavior.

Rollback can revert to the current single-string workspace naming and flat sidebar because the change is UI/model-scoped and has no external dependency migration.

## Open Questions

- Whether inactive workspaces should always show their terminal child rows or collapse by default.
- Whether sidebar child rows should show `repo · branch · path` or prioritize `branch · path` unless repository names are ambiguous.
- Whether additive control-plane or hook metadata is valuable in the same change or should wait until the UI settles.
