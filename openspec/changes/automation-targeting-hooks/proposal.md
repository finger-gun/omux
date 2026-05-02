## Why

OpenMUX now has user hook directories and a local control plane, but the automation surface is not yet powerful or reliable enough for real workflow composition: `omux events` can block other control-plane commands, `omux run` can type into Ghostty-backed panes without submitting, targets are hard to discover, and hooks cannot easily chain layout actions or feed useful responses back into terminals. This matters because OpenMUX promises a terminal-first, hackable workspace where users can build their own workflows without forking the app or waiting for every workflow to become core UI.

## Goals

- Make the control plane safe for hooks and event subscribers by preventing long-lived event streams from blocking normal commands.
- Make terminal targeting explicit and scriptable across session, pane, workspace, and focused-terminal concepts.
- Fix command injection so `omux run` reliably executes in runtime-backed and fallback terminal panes.
- Add raw terminal text input so hooks can insert messages without forcing command execution.
- Enrich CLI/action results with IDs for created/focused panes, sessions, tabs, and workspaces so hook scripts can chain actions deterministically.
- Add hook events and payload fields for command failure workflows, including enough command metadata for external analysis tools to react usefully.
- Document practical hook automation examples: workspace bootstrap layouts and command-failure AI analysis.

## Non-goals

- Do not add an embedded scripting runtime, browser-heavy plugin UI, or in-process plugin host.
- Do not make AI a privileged core workflow; AI agents remain ordinary hook/CLI/control-plane consumers.
- Do not expose libghostty enums, AppKit objects, or mutable internal workspace structures to hooks or CLI callers.
- Do not attempt full transcript persistence or complete command-output capture beyond a bounded tail/reference needed for first-wave command-failure automation.
- Do not replace the existing shared action model with hook stdout as the primary command bus.

## What Changes

- Fix the local control-plane server so long-running `omux events` subscriptions do not block commands such as `omux run`, `omux split`, or `omux notify`.
- Fix `session.runCommand` / `omux run` so runtime-backed panes submit the command rather than only inserting text into the prompt.
- Add public raw text input through JSON-RPC and CLI, e.g. `session.sendText` / `omux send-text`.
- Add explicit CLI target selectors for automation commands:
  - `--session <session-id>` for exact terminal sessions
  - `--pane <pane-id>` for visible pane/local pane-tab targets
  - `--tab <tab-id>` for the focused terminal inside a workspace tab
  - `--workspace <workspace-id>` for the focused terminal inside a workspace
  - `--focused` for the globally focused terminal
- Keep existing positional `omux run <session-id> <command>` compatibility while documenting the new selector form.
- Add discoverability commands or options, e.g. `omux sessions`, `omux panes`, and/or `omux list --full`, so users can find pane/session IDs without relying on hook payloads.
- Enrich action command responses so split/create/focus/run commands return machine-readable IDs for changed or focused entities, including created pane/session IDs where applicable.
- Add `command-failed` as a convenience hook emitted when command completion has a nonzero exit code, with OpenMUX-native identifiers and command metadata.
- Enrich command-started/finished/failed hook payloads with command text, cwd when available, exit status, duration, and bounded output tail or output reference when available.
- Update hook documentation with complete examples showing:
  - default workspace layout bootstrap with split/focus/run
  - command failure analysis via an external AI agent followed by writing a response back to the originating terminal

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `omux-control-plane`: Add non-blocking event stream handling, terminal target resolution, raw text input, richer discovery, and richer action result contracts.
- `workspace-session-actions`: Extend shared actions so automation can target sessions, panes, focused terminals within containers, and return created/focused IDs for chaining.
- `hooks-foundation`: Add command-failed automation semantics and enrich hook payloads so hooks can call back into OpenMUX safely through public actions.
- `terminal-action-dispatch`: Enrich command completion/failure events with command metadata and bounded output context while preserving the libghostty bridge boundary.
- `interactive-terminal-sessions`: Clarify reliable command execution versus raw text insertion for runtime-backed and fallback terminal sessions.

## Impact

- `OmuxControlPlane`: concurrent or otherwise non-blocking handling for long-lived event streams; new/updated JSON-RPC methods and response payloads.
- `OmuxCLI`: new target selector parsing, `send-text`, richer list/session/pane discovery, and compatibility for existing `omux run <session-id> <command>`.
- `OmuxAppShell`: target resolution across workspace/tab/pane/session structures and action result metadata.
- `OmuxTerminalBridge`: runtime-aware command submission that sends Return correctly while preserving keyboard/input correctness and bridge boundaries.
- `OmuxHooks`: new hook names/payload fields for command-failure automation.
- Documentation: expanded hook and CLI examples for composable workspace bootstrap and command failure analysis.
- Tests: control-plane concurrency, target resolution, command submission, send-text behavior, hook payload enrichment, and documentation-backed CLI examples.
