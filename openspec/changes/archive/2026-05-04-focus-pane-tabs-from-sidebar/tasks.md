## 1. Sidebar Pane-Tab Focus

- [x] 1.1 Update shared pane focus so a pane ID can be focused across all workspaces, activating the containing workspace and focused tab.
- [x] 1.2 Ensure failed pane focus requests remain inert and do not emit success-shaped focus events.
- [x] 1.3 Wire sidebar terminal metadata row clicks through the shared pane-tab focus path.

## 2. Menu Organization

- [x] 2.1 Split current View menu actions into Workspace, Pane, and View menus.
- [x] 2.2 Keep View scoped to visual shell/chrome controls.
- [x] 2.3 Preserve keybinding registry application, rebinding, unbinding, and validation for moved menu items.

## 3. Validation

- [x] 3.1 Add controller tests for focusing pane tabs in inactive workspaces and missing pane focus behavior.
- [x] 3.2 Add AppKit tests for sidebar terminal row click focus.
- [x] 3.3 Update AppKit menu tests for Workspace, Pane, and View placement.
- [x] 3.4 Run relevant Swift tests and `openspec validate focus-pane-tabs-from-sidebar --strict`.
