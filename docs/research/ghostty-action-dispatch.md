# Ghostty Action Dispatch in OpenMUX

## Executive summary

`libghostty` exposes an **action callback** through which the embedded engine asks the host to perform host-environment operations: setting window titles, opening URLs, ringing the bell, surfacing desktop notifications, reporting `pwd`, signalling that a shell command finished, and so on. There are roughly sixty distinct action types in the public C API, listed under `ghostty_action_tag_e` in `Vendor/ghostty/include/ghostty.h`.

OpenMUX currently rejects every action. In `Sources/OmuxTerminalBridge/CGhosttyRuntime.swift`, the runtime config is constructed with:

```swift
action_cb: { _, _, _ in false }
```

This is safe — it is the reason "Ghostty config keys that assume Ghostty owns the window" don't actually break OpenMUX, because the engine's app-shell requests are ignored. But it also means OpenMUX is currently leaving a meaningful chunk of modern terminal behavior on the table.

This note inventories the action surface and identifies which actions OpenMUX should eventually honor, defer, or continue rejecting. It does not propose a change; it captures the design space so a future `terminal-action-dispatch` change can be filed with the right scope.

## What is a Ghostty action

A Ghostty action is an **upcall** from the engine to the host. The engine itself does not own a window, a notification system, a clipboard interaction layer, or an updates pipeline. When something inside the terminal session — a key binding, a TUI program, an OSC sequence, a shell-integration event — wants the host environment to do something, the engine fires an action and asks the host to handle it via `action_cb`.

Three flavors are mixed in the same enum:

1. **App-shell requests.** "Open a new tab", "toggle fullscreen", "quit". These exist for Ghostty-as-standalone-app and are largely irrelevant when Ghostty is embedded.
2. **Session→host events.** "Set my title", "pwd changed", "ring the bell", "open this URL", "show a desktop notification", "this shell command just finished". These are real terminal-session signals that a host should normally honor.
3. **Engine state notifications.** "Renderer is unhealthy", "cell size is now N×M", "child process exited". These carry information the host needs to render, lay out, and recover correctly.

## Inventory by intended OpenMUX disposition

The following classification is based on the public action enum and OpenMUX architecture (workspaces, tabs, panes, pane-local tab stacks, hooks, JSON-RPC control plane).

### Reject (OpenMUX owns these — Ghostty does not)

These actions presume Ghostty manages the window/tab/app-chrome layer. OpenMUX manages that layer itself. They should remain rejected by default. A later change could optionally translate selected ones into native OpenMUX actions (for example, `NEW_SPLIT` could route to an OpenMUX pane split), but that is a feature, not a default.

- `QUIT`, `NEW_WINDOW`, `NEW_TAB`, `CLOSE_TAB`, `NEW_SPLIT`, `CLOSE_ALL_WINDOWS`, `CLOSE_WINDOW`
- `TOGGLE_MAXIMIZE`, `TOGGLE_FULLSCREEN`, `TOGGLE_TAB_OVERVIEW`, `TOGGLE_WINDOW_DECORATIONS`, `TOGGLE_QUICK_TERMINAL`, `TOGGLE_COMMAND_PALETTE`, `TOGGLE_VISIBILITY`, `TOGGLE_BACKGROUND_OPACITY`
- `MOVE_TAB`, `GOTO_TAB`, `GOTO_SPLIT`, `GOTO_WINDOW`, `RESIZE_SPLIT`, `EQUALIZE_SPLITS`, `TOGGLE_SPLIT_ZOOM`
- `PRESENT_TERMINAL`, `RESET_WINDOW_SIZE`, `INITIAL_SIZE`, `FLOAT_WINDOW`
- `OPEN_CONFIG`, `RELOAD_CONFIG` — OpenMUX uses its own config at `~/.omux/config.toml` and its own reload trigger
- `CHECK_FOR_UPDATES` — OpenMUX owns its update story

### Honor (real session signals worth surfacing)

These are the actions where doing nothing is a real product gap. The shortlist below in **High-leverage actions** flags the strongest candidates.

- `SET_TITLE`, `SET_TAB_TITLE` → pane and tab labels reflect the running command
- `PWD` → cwd-aware tab labels, "open in Finder", JSON-RPC `pane.cwd` events, hook context
- `DESKTOP_NOTIFICATION` → wrap `UNUserNotificationCenter`
- `OPEN_URL` → wrap `NSWorkspace.open()`
- `RING_BELL` → visual flash plus optional `NSSound.beep()`
- `MOUSE_SHAPE`, `MOUSE_VISIBILITY` → `NSCursor` over the pane region
- `MOUSE_OVER_LINK` → hover affordance / preview chrome
- `COMMAND_FINISHED` → shell integration: drives notifications, hooks, automation triggers
- `PROGRESS_REPORT` → OSC progress reports rendered in pane chrome (build status, test progress)
- `COLOR_CHANGE` → OSC palette mutation honored for the lifetime of the session
- `SHOW_CHILD_EXITED` → drives "session ended" pane state
- `RENDERER_HEALTH` → diagnostics, drives fallback transitions
- `CELL_SIZE` → layout sizing
- `RENDER`, `RENDER_INSPECTOR` → redraw signals

### Defer / reconsider

These are not obvious wins on first look and benefit from waiting until a related capability change is in flight.

- `KEY_SEQUENCE`, `KEY_TABLE` — multi-key binding state. Naturally belongs with `input-pipeline`, not a generic action dispatcher.
- `START_SEARCH`, `END_SEARCH`, `SEARCH_TOTAL`, `SEARCH_SELECTED` — Ghostty's in-terminal search. An open question whether OpenMUX adopts Ghostty's search or builds its own.
- `SCROLLBAR` — relevant only if OpenMUX adds visible scrollbars.
- `SECURE_INPUT` — password-entry indicator, useful as a hook signal once we have a secure-input UI.
- `READONLY` — surfaces a lockable-pane feature that does not yet exist.
- `COPY_TITLE_TO_CLIPBOARD` — trivial and safe; honor whenever convenient.
- `PROMPT_TITLE` — would require an AppKit prompt sheet; deferable.
- `INSPECTOR`, `SHOW_GTK_INSPECTOR` — Ghostty debug tooling, not for OpenMUX users.
- `SHOW_ON_SCREEN_KEYBOARD` — touch / iOS concern, irrelevant on macOS.
- `QUIT_TIMER` — app-shell quit confirmation, ignore.
- `UNDO`, `REDO` — likely belong to OpenMUX editor / sidebar surfaces, not the terminal pane.

## High-leverage actions

The actions with the largest payoff per unit of integration effort, given existing OpenMUX capabilities (`hooks-foundation`, `omux-control-plane`, workspace + pane-tab chrome):

| Action | Why it matters |
| --- | --- |
| `PWD` | Powers cwd-aware features: tab labels, "open in Finder", hook context, JSON-RPC `pane.cwd` events. Cheap, broad payoff. |
| `COMMAND_FINISHED` | Shell-integration goldmine. Drives notifications, hooks, automation triggers. Strongest candidate for the AI-friendly automation surface. |
| `DESKTOP_NOTIFICATION` | One-line wrapper to `UNUserNotificationCenter`. Users expect it. |
| `OPEN_URL` | One-line wrapper to `NSWorkspace.open()`. Users expect it. |
| `SET_TITLE` / `SET_TAB_TITLE` | Pane chrome reflecting the running command. |
| `RING_BELL` | Trivial, expected. |
| `PROGRESS_REPORT` | Modern terminals surface build / test progress in chrome. Differentiator. |
| `SHOW_CHILD_EXITED` / `RENDERER_HEALTH` | Pane state and diagnostics, already needed for fallback path quality. |

## Architectural notes for a future change

A future change introducing action dispatch should preserve the bridge boundary discipline already established for `terminal-bridge`:

- Define an OpenMUX-native action type. The bridge translates `ghostty_action_tag_e` into the OpenMUX type. Code outside the bridge does not see Ghostty action enums.
- Classify each action into reject / honor / translate at the bridge layer.
- Honored actions fan out through OpenMUX's existing surfaces: hooks for automation, JSON-RPC events on the control plane for external tools and AI workflows, and AppKit surfaces for user-visible behavior.
- Action handling is orthogonal to config and theme. The bridge's `action_cb` and the bridge's config loader are independent seams; a config-and-theme change does not need to touch action dispatch and vice versa.

## Config boundary note

Future work on action dispatch should assume the current config model is:

- users edit **`~/.omux/config.toml`**
- user themes live under **`~/.omux/themes/`**
- Ghostty config is a **generated internal artifact** under **`~/.omux/generated/ghostty/`**
- `[ghostty]` is an advanced pass-through section, but OpenMUX-managed keys still win on conflict
- v1 reload is **explicit** via `omux config reload`, not a background file-watcher

That means Ghostty actions like `OPEN_CONFIG` and `RELOAD_CONFIG` should continue to route to OpenMUX-owned config UX and reload behavior, not to Ghostty's standalone-app config assumptions.

See also: [`docs/configuration.md`](../configuration.md)

## Open questions

These belong with the change proposal, not with this note:

- Should bucket-1 actions ever be translated into native OpenMUX actions, and on what trigger (config opt-in, default-off command palette)?
- Search: honor Ghostty's search actions or build OpenMUX search?
- Per-action user opt-in / opt-out via config?
- How does action dispatch interact with the runtime fallback path when libghostty is unavailable?
