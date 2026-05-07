## Context

OpenMUX already treats workspaces, keybindings, actions, and the `omux` control plane as native product concepts. The command palette should compose those existing concepts into a fast keyboard-first overlay rather than becoming a separate launcher subsystem.

The palette has two search modes. Opening with `Cmd+P` starts in workspace mode with an empty query and lets the user search and switch workspaces. Opening with `Cmd+Shift+P`, or typing `>` as the first character, starts command mode and searches invokable shortcut-backed actions plus supported `omux` CLI commands.

The implementation must preserve terminal input correctness. Palette shortcuts are application commands, while normal text, Option-key combinations, dead keys, and IME composition must continue flowing to the focused terminal when the palette is not open.

## Goals / Non-Goals

**Goals:**

- Provide one native command palette overlay that supports workspace mode and command mode.
- Route workspace results through workspace/session action APIs.
- Route command results through OpenMUX action dispatch or explicit `omux` control-plane command invocations.
- Keep search local and lightweight for the initial implementation.
- Make command result metadata inspectable enough to support titles, shortcuts, categories, and enabled/disabled state.
- Keep `libghostty` details behind the existing terminal bridge boundary.

**Non-Goals:**

- Replacing shell completion, terminal command history, or in-terminal fuzzy finders.
- Introducing a browser/webview command UI.
- Adding plugin-provided palette items before the core action and CLI metadata contracts are stable.
- Running arbitrary shell strings from the palette without an explicit supported command contract.
- Adding persistent indexing or network-backed search.

## Decisions

### Use A Native App Overlay Owned By The App Shell

The palette should be a native macOS overlay presented by the AppKit shell, with SwiftUI acceptable for the non-terminal chrome if that matches nearby UI patterns. The overlay owns focus only while open and restores focus to the previously focused terminal, pane, or workspace surface when dismissed or after invocation.

Alternative considered: render the palette inside the terminal engine surface. This was rejected because it would couple application chrome to terminal rendering, complicate focus restoration, and risk leaking `libghostty` concepts into product-level command handling.

### Model Search As Providers Selected By Prefix

Palette search should use a small provider interface with a mode derived from the query prefix:

- No `>` prefix uses the workspace provider.
- A leading `>` uses the command provider and strips the prefix before matching.
- `Cmd+P` opens with an empty query.
- `Cmd+Shift+P` opens with `>` prefilled and the insertion point after the prefix.

Alternative considered: separate UI commands for separate palettes. This was rejected because a single palette with an explicit prefix is easier to learn, inspect, and extend while still keeping the default workspace flow fast.

### Keep Command Invocation On Existing Boundaries

Shortcut-backed commands should be discovered from action/keybinding metadata and invoked through terminal action dispatch. CLI-backed commands should be discovered from an explicit supported `omux` command metadata contract and invoked through the control plane, not by constructing ad hoc shell commands.

Alternative considered: treat every palette command as a CLI string. This was rejected because it bypasses existing typed action dispatch, makes enabled/disabled state harder to represent, and creates avoidable quoting and security risks.

### Make Result Metadata Explicit

Palette results should use OpenMUX-native metadata: stable identifier, title, optional subtitle, category, match text, optional shortcut label, enabled state, and invocation target. Workspaces, shortcut-backed actions, and CLI-backed commands can provide different invocation targets while sharing a common presentation and selection model.

Alternative considered: return display strings only. This was rejected because display-only results make keyboard shortcuts, disabled states, telemetry/debugging, and future extension points harder to implement predictably.

### Preserve Keyboard Correctness Before Terminal Dispatch

`Cmd+P` and `Cmd+Shift+P` should be resolved as application-level shortcuts before terminal text input dispatch. The implementation must avoid interpreting Option-modified input as palette shortcuts and must not interrupt active IME composition unless the user presses a recognized command shortcut.

Alternative considered: capture key equivalents inside the terminal view. This was rejected because terminal input handling already has layout-sensitive behavior and should not gain palette-specific branching.

## Risks / Trade-offs

- Shortcut conflicts with terminal applications using `Cmd+P` or custom keybindings -> Mitigation: route through configurable keybinding defaults and preserve an override path.
- Command metadata may drift from actual CLI support -> Mitigation: derive palette-visible CLI commands from the same control-plane command descriptors used by the `omux` implementation where possible.
- Disabled or context-sensitive actions may appear confusing -> Mitigation: include enabled state and optional disabled reason in command result metadata.
- Palette focus handling can break terminal input after dismissal -> Mitigation: explicitly store and restore the previously focused responder/surface and add UI tests for open, dismiss, and invoke flows.
- Large workspace or command lists could make search feel slow -> Mitigation: keep matching in-memory, debounce only if needed, and avoid background indexing for the initial scope.
- Prefix-based command mode may conflict with workspace names starting with `>` -> Mitigation: treat only the first character as a reserved mode prefix in the palette query and document escaping/renaming behavior if it becomes necessary.

## Migration Plan

- Add palette UI and search model behind default keybindings without changing existing workspace, action, or CLI behavior.
- Add discoverable metadata to existing action and CLI command registries incrementally, exposing only supported commands in the palette.
- Keep existing direct shortcuts and `omux` CLI invocations working unchanged.
- Roll back by removing the default palette keybindings and hiding the palette entry points while leaving action/control-plane contracts intact.

## Open Questions

- Which exact `omux` CLI commands are safe and useful enough to expose in the initial command-mode result set?
- Should disabled command results be shown by default, hidden, or shown only when the query exactly matches?
- Should workspace matching include persisted inactive workspaces only, currently open workspaces only, or both?
