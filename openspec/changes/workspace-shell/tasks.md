## 1. Real terminal pane hosting

- [x] 1.1 Replace the placeholder pane view with a real terminal-hosting AppKit view backed by the terminal bridge.
- [x] 1.2 Extend the bridge and shell integration so pane creation attaches live terminal surfaces and sessions through OpenMUX abstractions.
- [x] 1.3 Add validation coverage that confirms pane hosting uses the bridge boundary rather than direct libghostty calls from shell/UI code.

## 2. Native workspace layout

- [x] 2.1 Introduce the first tabs-and-splits workspace layout model in the AppKit shell.
- [x] 2.2 Implement explicit active-tab and active-pane focus transitions in the workspace model and shell.
- [x] 2.3 Add validation coverage for workspace layout and focus behavior across tabs and split panes.

## 3. Shared workspace and session actions

- [x] 3.1 Define shared workspace/session operations for open-workspace, create-tab, split-pane, focus-session, and run-command.
- [x] 3.2 Connect the native shell to those shared operations instead of duplicating action logic in the UI layer.
- [x] 3.3 Extend `omux` and the JSON-RPC control plane to expose the same first-phase workspace/session actions.

## 4. Input and usability validation

- [x] 4.1 Route live terminal pane input through the normalized input pipeline before terminal dispatch.
- [x] 4.2 Add validation coverage for Option/Alt behavior, right-Option-sensitive flows, and dead-key/composition behavior in terminal-backed panes.
- [x] 4.3 Update developer-facing documentation to reflect the first usable workspace shell and how future changes should build on it.
