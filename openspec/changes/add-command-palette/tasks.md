## 1. Palette Model And Search

- [ ] 1.1 Define command palette query mode parsing so an empty or non-prefixed query uses workspace mode and a leading `>` uses command mode with the prefix stripped for matching
- [ ] 1.2 Define shared palette result metadata with stable identifier, title, category, match text, enabled state, invocation target, and optional subtitle, shortcut label, and disabled reason
- [ ] 1.3 Implement local in-memory workspace result matching without background indexing, network access, browser UI, or webview dependencies
- [ ] 1.4 Implement local in-memory command result matching across shortcut-backed actions and supported `omux` CLI command metadata

## 2. Action And Control Metadata

- [ ] 2.1 Add palette-visible metadata for supported shortcut-backed OpenMUX actions without exposing AppKit event objects or terminal-engine types
- [ ] 2.2 Route shortcut-backed palette selections through the existing action dispatch path used by effective keyboard shortcuts
- [ ] 2.3 Add explicit palette-invokable metadata for supported `omux` CLI commands, including argument requirements, enabled state, and invocation target
- [ ] 2.4 Route CLI-backed palette selections through the local JSON-RPC control-plane operation contract rather than arbitrary shell command execution
- [ ] 2.5 Ensure disabled or context-invalid command results are represented before invocation and are not dispatched when selected

## 3. Workspace Integration

- [ ] 3.1 Expose switchable workspace metadata for palette search, including stable workspace ID, display name, optional path, and active state
- [ ] 3.2 Invoke selected workspace results through the shared workspace/session action model
- [ ] 3.3 Return structured failures for stale or missing workspace selections without changing the active workspace
- [ ] 3.4 Verify typing workspace search queries is read-only and does not mutate workspaces, panes, sessions, or terminal input

## 4. Keybindings And Input Routing

- [ ] 4.1 Add default `Cmd+P` binding for opening the command palette with an empty query in workspace mode
- [ ] 4.2 Add default `Cmd+Shift+P` binding for opening the command palette with `>` prefilled in command mode
- [ ] 4.3 Preserve existing user override behavior so either palette shortcut can be rebound or mapped to `none`
- [ ] 4.4 Route effective palette shortcuts as application commands before terminal text input dispatch from focused terminal panes
- [ ] 4.5 Add regression coverage showing palette routing does not claim Option-modified input, right-Option layout text, dead-key composition, or IME preedit when the palette is closed

## 5. Native Palette UI

- [ ] 5.1 Implement a native macOS command palette overlay owned by the app shell, using AppKit with SwiftUI only for non-terminal chrome if consistent with nearby UI
- [ ] 5.2 Open the palette from `Cmd+P` with an empty search field, workspace results, and focus in the search field
- [ ] 5.3 Open the palette from `Cmd+Shift+P` with `>` prefilled, command results, and the insertion point after the prefix
- [ ] 5.4 Switch result providers live when the user adds or removes the leading `>` prefix
- [ ] 5.5 Keep palette query text inside the palette while open and prevent it from being sent to the focused terminal session
- [ ] 5.6 Restore focus to the previously focused terminal, pane, or workspace surface after dismissal or successful invocation

## 6. Validation And Documentation

- [ ] 6.1 Add unit tests for query mode parsing, prefix removal, result matching, enabled state handling, and invocation target selection
- [ ] 6.2 Add integration tests for `Cmd+P`, `Cmd+Shift+P`, selecting workspace results, selecting shortcut-backed commands, and selecting CLI-backed commands
- [ ] 6.3 Add keyboard/input regression tests covering focused terminal shortcut routing, Option/right-Option preservation, dead keys, and IME composition behavior
- [ ] 6.4 Run the relevant Swift test suite and app-shell validation commands for the changed modules
- [ ] 6.5 Update user-facing keybinding or command documentation to describe `Cmd+P`, `Cmd+Shift+P`, workspace search, and `>` command search
