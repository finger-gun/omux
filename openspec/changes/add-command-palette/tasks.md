## 1. Palette Model And Search

- [ ] 1.1 Define command palette query mode parsing so an empty or non-prefixed query uses workspace mode and only a first-character `>` uses command mode with the prefix stripped for matching
- [ ] 1.2 Define shared palette result metadata with stable identifier, title, category, match text, aliases, enabled state, invocation target, and optional subtitle, shortcut label, and disabled reason
- [ ] 1.3 Implement deterministic ranked local workspace result matching for currently open workspaces, matching display names and paths with visible order as the stable tiebreaker
- [ ] 1.4 Implement deterministic ranked local command result matching across safe discoverable actions and supported safe-default `omux` CLI command metadata

## 2. Action And Control Metadata

- [ ] 2.1 Add palette-visible metadata for supported safe OpenMUX actions without exposing AppKit event objects or terminal-engine types, including shortcut labels when available
- [ ] 2.2 Route safe action palette selections through the existing action dispatch path used by effective keyboard shortcuts
- [ ] 2.3 Add explicit palette-invokable metadata for supported safe-default `omux` CLI commands, including aliases, argument requirements, enabled state, and invocation target
- [ ] 2.4 Route CLI-backed palette selections through shared typed control APIs rather than arbitrary shell command execution, `omux` subprocesses, or app JSON-RPC loopback
- [ ] 2.5 Hide argument-requiring actions and CLI commands unless they have safe focused/default targets
- [ ] 2.6 Ensure disabled or context-invalid command results are represented before invocation and are not dispatched when selected

## 3. Workspace Integration

- [ ] 3.1 Expose currently open switchable workspace metadata for palette search, including stable workspace ID, display name, optional path, visible order, and active state
- [ ] 3.2 Invoke selected non-current workspace results through the shared workspace/session action model
- [ ] 3.3 Return structured failures for stale or missing workspace selections without changing the active workspace
- [ ] 3.4 Treat selecting the active workspace as inert, closing the palette and restoring focus without emitting a switch event
- [ ] 3.5 Verify typing workspace search queries is read-only and does not mutate workspaces, panes, sessions, or terminal input

## 4. Keybindings And Input Routing

- [ ] 4.1 Add default `Cmd+P` binding for opening the command palette with an empty query in workspace mode
- [ ] 4.2 Add default `Cmd+Shift+P` binding for opening the command palette with `>` prefilled in command mode
- [ ] 4.3 Preserve existing user override behavior so either palette shortcut can be rebound or mapped to `none`
- [ ] 4.4 Allow palette shortcuts mapped to `none` to pass through existing terminal input routing when representable
- [ ] 4.5 Route effective palette shortcuts as application commands before terminal text input dispatch from focused terminal panes
- [ ] 4.6 Add regression coverage showing palette routing does not claim Option-modified input, right-Option layout text, dead-key composition, or IME preedit when the palette is closed

## 5. Native Palette UI

- [ ] 5.1 Implement a native macOS command palette overlay owned by the app shell, using AppKit with SwiftUI only for non-terminal chrome if consistent with nearby UI
- [ ] 5.2 Open the palette from `Cmd+P` with an empty search field, all open workspaces listed, and focus in the search field
- [ ] 5.3 Open the palette from `Cmd+Shift+P` with `>` prefilled, safe command results listed, and the insertion point after the prefix
- [ ] 5.4 Switch result providers live when the user adds or removes the leading `>` prefix
- [ ] 5.5 Keep palette query text inside the palette while open and prevent it from being sent to the focused terminal session
- [ ] 5.6 Restore focus to the previously focused terminal, pane, or workspace surface after dismissal or successful invocation
- [ ] 5.7 Reset an already-open palette to the shortcut-implied mode when `Cmd+P` or `Cmd+Shift+P` is invoked again
- [ ] 5.8 Support Return, Escape, keyboard navigation, and mouse click selection with native accessible result row controls

## 6. Validation And Documentation

- [ ] 6.1 Add unit tests for query mode parsing, first-character prefix behavior, prefix removal, result ranking, enabled state handling, and invocation target selection
- [ ] 6.2 Add integration tests for `Cmd+P`, `Cmd+Shift+P`, selecting workspace results, selecting safe action commands, selecting CLI-backed commands, and active-workspace inert selection
- [ ] 6.3 Add keyboard/input regression tests covering focused terminal shortcut routing, Option/right-Option preservation, dead keys, and IME composition behavior
- [ ] 6.4 Run the relevant Swift test suite and app-shell validation commands for the changed modules
- [ ] 6.5 Update user-facing keybinding or command documentation to describe `Cmd+P`, `Cmd+Shift+P`, workspace search, and `>` command search
