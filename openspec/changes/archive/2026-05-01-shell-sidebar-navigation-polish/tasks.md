## 1. Workspace naming model

- [x] 1.1 Add explicit generated-name and custom-name semantics to workspace models while preserving a stable display-name accessor.
- [x] 1.2 Update workspace creation and rename flows to allocate `Workspace N` labels, apply custom overrides, and support removing a custom name.
- [x] 1.3 Extend workspace summaries or shell-facing view models so sidebar rendering can consume generated/custom naming state without string heuristics.

## 2. Sidebar terminal metadata

- [x] 2.1 Add shell-side terminal metadata types and a git metadata resolver that derives repo/branch/path information from workspace or pane paths without bridge changes.
- [x] 2.2 Add caching and refresh triggers so terminal metadata updates on workspace activation and cwd dispatch events without continuous background polling.
- [x] 2.3 Refactor sidebar rendering from flat workspace rows to workspace rows plus terminal child rows with subtle metadata styling and terminal-focus navigation.

## 3. Contextual shell actions

- [x] 3.1 Introduce shared action builders or controllers for workspace-row context menus, including rename, close, close others, close above, close below, and remove custom name enablement.
- [x] 3.2 Add pane-tab context menus with local rename and close-oriented actions that follow pane-stack ordering semantics.
- [x] 3.3 Preserve existing menu-bar actions and keyboard shortcuts while wiring new context menus through standard AppKit interaction paths.

## 4. Pane chrome identity polish

- [x] 4.1 Update pane status rendering so cwd-only identity text no longer keeps a persistent secondary row alive.
- [x] 4.2 Preserve transient status rendering for progress, exit state, and renderer health after the cwd-only suppression change.

## 5. Validation and documentation

- [x] 5.1 Add or update tests for generated workspace naming, custom-name reset behavior, sidebar metadata fallbacks, and context-menu action availability.
- [x] 5.2 Add UI-focused tests for terminal child-row navigation, pane-tab context actions, and cwd-only status-row suppression.
- [x] 5.3 Validate that context-menu integration does not regress existing keyboard shortcuts or focus behavior on shell surfaces.
- [x] 5.4 Update relevant development or architecture docs to describe workspace naming semantics, sidebar metadata derivation, and the decision to keep git logic out of the terminal bridge.
