# Feature Suggestions

This document lists feature suggestions derived from reviewing open issues and pull requests in the cmux GitHub repository. Items already implemented in omux have been excluded.

Sources reviewed:
- https://github.com/manaflow-ai/cmux/issues
- https://github.com/manaflow-ai/cmux/pulls
- https://www.reddit.com/r/cmux/

---

## Session & Workspace Management

| Feature                                                                                                                                                                          | Priority | cmux ref              |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------|
| **Snooze/hide a workspace** — temporarily remove a workspace from the sidebar without closing it                                                                                 | Medium   | Issue #4261, PR #4265 |
| **Stable `TERM_SESSION_ID` per pane across restarts** — inject a stable `TERM_SESSION_ID` env var per pane so tools like Atuin can scope shell history to a pane across sessions | Medium   | Issue #4006           |

---

## Terminal Correctness

| Feature                                                                                                                          | Priority | cmux ref    |
|----------------------------------------------------------------------------------------------------------------------------------|----------|-------------|
| **Ctrl+G (BEL) forwarding** — ensure BEL (`\a`, `0x07`) is forwarded to the terminal and not consumed in the event routing chain | High     | Issue #4217 |
| **Terminal input during window drags** — terminal should remain interactive while the window is being dragged                    | Medium   | PR #4281    |

---

## CLI & Scripting

| Feature                                                                                                                                                                                 | Priority | cmux ref    |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-------------|
| **Scoped event streams** — allow `omux events` to filter by workspace, tab, or pane ID (e.g. `omux events --workspace <id>`)                                                            | High     | PR #4304    |
| **Non-focusing CLI commands** — add a `--no-focus` flag (or make it default) for commands like `omux split`, `omux open`, `omux tab` so they don't steal focus from the current surface | Medium   | PR #4297    |
| **Settings read/write via CLI** — extend `omux config` to allow reading and writing individual settings (e.g. `omux config get ui.panes.inactive_opacity`, `omux config set ...`)       | Medium   | Issue #3806 |

---

## Keyboard & Input

| Feature                                                                                                                                                                  | Priority | cmux ref            |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|---------------------|
| **Command palette keyboard focus** — ensure the command palette captures all keystrokes immediately on open; keystrokes must not leak to the terminal surface underneath | High     | Issue #4303         |
| **Tab-level fuzzy switcher** — `cmd+p` covers workspace switching; add a tab/pane-level switcher within the active workspace                                             | Medium   | Issues #3724, #3009 |
| **Two-finger swipe between workspaces** — trackpad swipe gesture to cycle through workspaces                                                                             | Low      | Issues #2557, #3029 |
| **Copy on select** — make copy-on-select a first-class omux config option (not just a Ghostty passthrough)                                                               | Low      | Issue #2911         |
| **Keyboard hint navigation** — hint-mode overlay for jumping to UI elements without a mouse (vimium-style)                                                               | Low      | Issue #2554         |
| **Keyboard bindings to navigate notifications** — allow navigating and dismissing notifications using the keyboard                                                       | Low      | Issue #3008         |

---

## Hooks & Extension Points

| Feature                                                                                                                                                        | Priority | cmux ref    |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-------------|
| **Suppress notifications when app is focused** — option to suppress in-app or desktop notifications when the omux window is the frontmost application          | Medium   | Issue #3126 |
| **Workspace title in "Needs Input" notifications** — include the workspace name and pane title in notification payloads for the `needs-input` status           | Medium   | Issue #3090 |
| **Cross-workspace agent panel** — an extension pane or sidebar panel that aggregates pane status across all workspaces (running agents, needs-input, progress) | Low      | Issue #4356 |

---

## UX Polish (native macOS)

| Feature                                                                                                                       | Priority | cmux ref              |
|-------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------|
| **Unread notification badge on app icon** — show a badge on the Dock icon when there are unread or needs-input notifications  | Medium   | PR #4336              |
| **Native macOS "Services" menu** — wire up the macOS Services menu on right-click in the terminal surface                     | Low      | Issue #2698           |
| **Force-click "Look Up" / dictionary popover** — support the macOS force-click gesture for dictionary lookup on terminal text | Low      | Issue #4344, PR #4346 |
| **Configurable pane divider thickness** — allow users to set the visual width of split pane dividers                          | Low      | Issue #4311           |

---

## Keyboard & Input (Reddit)

| Feature                                                                                                                                                    | Priority | Reddit signal               |
|------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------|
| **tmux-style leader key** — support a configurable leader key (e.g. `ctrl+a`, `ctrl+b`) as a prefix for key chord sequences, for users migrating from tmux | Medium   | r/cmux (score 1–2, 2 posts) |

---

## UX Polish — Reddit

| Feature                                                                                                                                 | Priority | Reddit signal    |
|-----------------------------------------------------------------------------------------------------------------------------------------|----------|------------------|
| **Sidebar/chrome font size** — allow independent font size configuration for the sidebar and UI chrome, separate from the terminal font | Low      | r/cmux (score 2) |

---

## AI-Friendly Design

| Feature                                                                                                                                                                                                           | Priority | Reddit signal                |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|------------------------------|
| **Agent context injection** — expose omux workspace/pane state to AI coding agents running inside it (e.g. via an `OMUX_*` env vars, an `AGENTS.md`-style context file, or a local API endpoint agents can query) | Medium   | r/cmux (score 2, 2 comments) |

---

## Notes

- AI-vendor-specific integrations (Claude, Codex, Gemini, Grok deep integrations) were intentionally excluded — omux treats all agents as peers via hooks and CLI, not baked-in surfaces.
- Embedded browser pane features were excluded as they fall outside the terminal-first scope of omux.
- All priority assignments are relative to the omux north star: terminal fidelity, keyboard correctness, workspace/session model clarity, and CLI/RPC clarity.
