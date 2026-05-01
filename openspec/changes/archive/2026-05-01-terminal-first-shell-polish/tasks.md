## 1. Simplify shell chrome

- [x] 1.1 Remove the in-window top bar from `WorkspaceWindowController` and rely on config-owned theme selection instead of replacement shell controls
- [x] 1.2 Flatten `WorkspaceCanvasView` and `PaneCardView` styling by removing or materially reducing nested rounded borders and excess padding
- [x] 1.3 Simplify pane-header controls so pane-local navigation remains available with less pill/button chrome

## 2. Add shell state for navigation polish

- [x] 2.1 Add persisted OpenMUX-owned sidebar visibility state and wire `WorkspaceWindowController` layout updates so the content area expands when the workspace column is hidden
- [x] 2.2 Extend `WorkspaceController` with direct workspace selection by visible order and previous-active workspace recall helpers
- [x] 2.3 Update shell rendering/state flow so workspace switching and sidebar visibility changes refresh the visible shell consistently

## 3. Update window and shortcut behavior

- [x] 3.1 Update AppKit window configuration so the titlebar/background visually blends with the shell surface
- [x] 3.2 Remap split commands to `Cmd+D` and `Cmd+Shift+D`, preserve `Cmd+N`, and add `Cmd+B`, `Cmd+1` through `Cmd+9`, and `Cmd+0` shell commands
- [x] 3.3 Validate that shell shortcuts stay distinct from terminal text input in focused panes, including ISO/EU and Option-sensitive keyboard behavior

## 4. Documentation and verification

- [x] 4.1 Update shell/development docs to describe the simplified shell chrome and new workspace navigation shortcuts
- [x] 4.2 Add or update tests for sidebar toggle behavior, ordered workspace jumps, previous-active workspace recall, and shortcut routing
- [x] 4.3 Verify the shell polish change leaves terminal bridge ownership untouched and does not regress existing workspace/session actions
