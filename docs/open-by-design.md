# Open by Design

OpenMUX is built to be hookable from day one. The [manifesto](./manifest.md) puts it directly: "the goal is not to build everything — the goal is to make everything buildable."

This page tracks how well the project delivers on that goal. It maps every user-observable state transition to the three surfaces that make it buildable by external tools: hooks, control plane events, and CLI verbs. Transitions without full coverage are opportunities for future work. The project deliberately ships working features first and wires openness incrementally.

## The three surfaces

OpenMUX exposes three complementary automation surfaces. A fully open transition is wired into all three.

**Hooks** are push notifications to user-installed executables under `~/.omux/hooks/`. When a transition happens, OpenMUX launches registered handlers and pipes a JSON payload to stdin. Hooks are for reactions: "when a command fails, notify me." See the [hook reference](./hooks.md).

**Control plane events** are structured messages on the `omux events` JSON-RPC stream. A long-running process (dashboard, status widget, monitoring script) subscribes once and filters the stream. Events are for observation without per-occurrence process overhead. See the [event reference](./events.md).

**CLI verbs** are the pull interface: query state, trigger actions, inspect the workspace. `omux split`, `omux run`, `omux config get`. CLI verbs are for scripts and tools that want to make something happen or inspect current state on demand.

When all three surfaces are wired, external tools can observe a transition (events), react to it (hooks), and trigger the same action themselves (CLI). That is what "buildable" means in practice.

## Coverage

Each row is an action that OpenMUX supports or could support. Rows grouped by category. ✅ means wired, empty means not yet wired, and `n/a` means the surface does not apply to that action.

### Workspace lifecycle

| Action | Hook | Event | CLI | Notes |
| --- | --- | --- | --- | --- |
| Open workspace | ✅ | ✅ | ✅ | Fully wired. |
| Close workspace | ✅ | ✅ | ✅ | Fully wired. |
| Rename workspace | ✅ | | | Hook only. No event, no CLI verb. |
| Switch workspace focus | | | | Most common workspace action. Not observable. |
| Reorder workspace | | | | Move up/down has no external signal. |
| Restore workspace | ✅ | ✅ | ✅ | Fully wired. |

### Pane and tab actions

| Action | Hook | Event | CLI | Notes |
| --- | --- | --- | --- | --- |
| Create tab | ✅ | ✅ | ✅ | Fully wired. |
| Split pane | ✅ | ✅ | ✅ | Fully wired. |
| Create pane tab | ✅ | ✅ | ✅ | Fully wired. |
| Close pane tab | ✅ | ✅ | ✅ | Fully wired. |
| Focus pane tab | | ✅ | ✅ | Event and CLI exist, no hook. |
| Focus pane | ✅ | ✅ | ✅ | Fully wired. `omux pane-next`, `pane-prev`, and `focus --pane` cover this. |
| Remove pane | ✅ | ✅ | ✅ | Fully wired. |
| Resize pane | | | | Equalize and directional resize have no external signal. |
| Set/clear pane alias | ✅ | ✅ | ✅ | Fully wired. |

### Terminal session

| Action | Hook | Event | CLI | Notes |
| --- | --- | --- | --- | --- |
| Change working directory | ✅ | ✅ | n/a | Terminal process owns its cwd. |
| Set title | ✅ | ✅ | | Hook and event exist. No CLI verb to set a pane title. |
| Set tab title | ✅ | ✅ | | Hook and event exist. No CLI verb to set a tab title. |
| Start command | ✅ | ✅ | ✅ | Fully wired. |
| Finish command | ✅ | ✅ | | External tools could report command completion to OpenMUX. |
| Fail command | ✅ | | | External tools could report command failure to OpenMUX. |
| Report progress | ✅ | ✅ | | Scripts could drive the progress indicator. |
| Exit child process | ✅ | ✅ | | Scripts could terminate a pane's running process. |
| Change renderer health | ✅ | ✅ | n/a | Runtime signal. |
| Send input | ✅ | ✅ | ✅ | Fully wired. `omux run` and `send-text` trigger it. |
| Activate text | ✅ | ✅ | | Hook and event on Command-click. Could be triggered programmatically. |

### UI and host actions

| Action | Hook | Event | CLI | Notes |
| --- | --- | --- | --- | --- |
| Raise notification | ✅ | ✅ | ✅ | Fully wired. |
| Open URL | ✅ | ✅ | | Hook and event exist. CLI could route through OpenMUX's hook pipeline. |
| Show desktop notification | ✅ | ✅ | n/a | Terminal-originated. `omux notify` covers the CLI path. |
| Ring bell | ✅ | ✅ | | Hook and event exist. |
| Update pane status | ✅ | ✅ | ✅ | Fully wired. |
| Toggle sidebar | | | | No external signal. No CLI verb. |
| Toggle pane tab bar | | | | No external signal. No CLI verb. |

### Extension panes

| Action | Hook | Event | CLI | Notes |
| --- | --- | --- | --- | --- |
| Create extension pane | ✅ | ✅ | ✅ | Fully wired. |
| Update extension pane | ✅ | ✅ | ✅ | Fully wired. |
| Close extension pane | ✅ | ✅ | ✅ | Fully wired. |

### App lifecycle

| Action | Hook | Event | CLI | Notes |
| --- | --- | --- | --- | --- |
| Start app | | | | No signal that OpenMUX is ready. |
| Quit app | | | | No signal for cleanup before exit. |
| Reload config | ✅ | ✅ | ✅ | Emits `config-reloaded` and `config.reloaded` on successful completion. |

## How to wire a new transition

When adding a state transition or noticing an empty cell in the table above, the wiring pattern is consistent. The `pane-created` / `pane.split` transition is a good reference because it covers all three surfaces. Controller-owned wiring should attach through `WorkspaceControllerPublication` in `Sources/OmuxAppShell/WorkspaceControllerPublication.swift` so new hook and event surfaces do not drift back into ad hoc inline emission paths.

1. **Hook invocation.** In `WorkspaceController.swift`, route hook emission through the publication seam with `publication.emitHook(HookInvocation(...))`. Follow the naming convention: lifecycle hooks use `workspace-*` or `pane-*` prefixes, terminal hooks use `terminal-*` prefixes.

2. **Control plane event.** In the same method, call `publishControlPlaneEvent(ControlPlaneEvent(name: ..., ...))`, which now routes through the same publication seam. If the event name does not exist yet, add it to `ControlPlaneTerminalEventName` or `ControlPlaneActionEventName` in `Sources/OmuxControlPlane/TerminalEvents.swift`.

3. **CLI verb.** If the transition can be triggered by external tools (not just observed), add a case to `ControlMethod` in `Sources/OmuxControlPlane/JSONRPC.swift` and handle it in `OpenMUXControlPlaneService`. Wire the corresponding `omux` subcommand in `Sources/OmuxCLI/OmuxCLI.swift`.

4. **Documentation.** Add the hook to the hook name tables in `docs/hooks.md`. Update the coverage row in this file.

## Payload design

Hook and event payloads should use OpenMUX-native identifiers and values. A few guidelines for transitions that carry sensitive content:

- Terminal text (clipboard content, selection, scrollback) can contain secrets. Payloads that include terminal text should be bounded and intentional rather than streaming full content by default.
- Per-keystroke input is noisy, sensitive, and not an authoritative record. `terminal-input-sent` deliberately covers only explicit actions like `omux run` and `send-text`, not native typing.
- Hook payloads are delivered to local executables the user installed. The trust boundary is the user's own filesystem, not a network API.

These are design considerations for contributors wiring new transitions, not a capability system. The [hook reference](./hooks.md#boundary-rules) covers the full boundary rules.
