# OpenMUX Hooks

OpenMUX hooks are user-provided executable files that react to OpenMUX-native events. Hooks are external processes: OpenMUX does not embed Bash, TypeScript, Deno, Node, Lua, a browser runtime, or WebAssembly for this feature.

New to OpenMUX? Start with [Getting started](./getting-started.md). This page is the full hook reference once you are ready to automate your workspace.

The protocol is the platform:

- hook handlers are executable files
- handlers choose their own runtime through a shebang or native executable format
- OpenMUX sends one JSON invocation on stdin
- handlers use normal local side effects, `omux`, or the JSON-RPC control plane if they want to act on OpenMUX

## Directory layout

OpenMUX discovers hooks under **`~/.omux/hooks/`**. Each direct child directory is a hook name, and each executable regular file inside that directory is one handler for that hook.

```text
~/.omux/hooks/
  terminal-command-finished/
    10-log-duration
    20-notify-on-failure
  workspace-opened/
    10-bootstrap-layout
```

Multiple handlers for the same hook run in lexicographic filename order. Use numeric prefixes when order matters:

```text
10-log
20-notify
90-cleanup
```

OpenMUX ignores:

- hidden entries such as `.disabled`
- non-executable files such as `README.md`
- subdirectories inside a hook-name directory

If one handler fails to launch or exits nonzero, OpenMUX reports a warning and continues running later handlers for the same hook. Hook failures do not fail the underlying OpenMUX action.

In the production app, hook handlers run asynchronously on a background queue. OpenMUX does not block workspace creation, pane actions, or terminal events while waiting for hook processes to finish. Handlers for the same invocation still run in lexicographic order.

OpenMUX also enriches hook `PATH` before launch so hooks work when the app is started from Finder or `/Applications`, where macOS provides a minimal GUI environment. The hook path includes the app bundle executable directory, `~/.local/bin`, `~/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, and the standard system paths. This lets hooks call installed tools such as `omux`, `jq`, `deno`, or `python3` without hardcoding absolute paths in most setups.

## Handler format

A handler can be any executable file. OpenMUX launches the handler directly.

Shell example:

```bash
#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
exit_code="$(printf '%s' "$payload" | jq -r '.payload.exitCode')"

if [ "$exit_code" != "0" ] && [ "$exit_code" != "null" ]; then
  osascript -e "display notification \"Command failed with exit $exit_code\" with title \"OpenMUX\""
fi
```

Deno TypeScript example:

```ts
#!/usr/bin/env -S deno run --allow-run=osascript

const input = await new Response(Deno.stdin.readable).text()
const event = JSON.parse(input)
const exitCode = event.payload.exitCode

if (exitCode !== 0 && exitCode !== null) {
  await new Deno.Command("osascript", {
    args: [
      "-e",
      `display notification "Command failed with exit ${exitCode}" with title "OpenMUX"`,
    ],
  }).output()
}
```

After creating a hook handler, make it executable:

```bash
chmod +x ~/.omux/hooks/terminal-command-finished/20-notify-on-failure
```

## Invocation JSON

Every handler receives a `HookInvocation` JSON object on stdin.

```json
{
  "category": "command",
  "name": "terminal-command-finished",
  "workspaceID": "workspace-...",
  "tabID": "tab-...",
  "paneID": "pane-...",
  "sessionID": "session-...",
  "payload": {
    "command": "pnpm test",
    "cwd": "/Users/alice/project",
    "exitCode": 1,
    "durationNanoseconds": 1230000000,
    "outputContext": {
      "kind": "tail",
      "tail": "last bounded output..."
    }
  },
  "occurredAt": "2026-05-02T00:50:00Z"
}
```

Common fields:

| Field | Meaning |
| --- | --- |
| `category` | Hook category: `lifecycle`, `session`, `command`, `ui`, or `input`. |
| `name` | Hook name, matching the directory under `~/.omux/hooks/`. |
| `workspaceID` | Workspace identifier when the event has workspace context; otherwise `null` or absent after decoding. |
| `tabID` | Tab identifier when available. |
| `paneID` | Pane identifier when available. |
| `sessionID` | Terminal session identifier when available. |
| `payload` | Hook-specific OpenMUX-native payload object. |
| `occurredAt` | Time the hook invocation was created. |

The JSON payload is the source of truth. Environment variables may be added later for convenience, but hooks should not depend on them today.

## Calling back into OpenMUX

Hooks mutate OpenMUX by calling the public `omux` CLI or local JSON-RPC control plane. Hook stdout is ordinary process output; OpenMUX does not interpret stdout as a command protocol.

Terminal-targeting commands accept one explicit selector:

| Selector | Meaning |
| --- | --- |
| `--session <session-id>` | Target one exact terminal session. |
| `--pane <pane-id>` | Target the active local pane tab/session in a pane. |
| `--tab <tab-id>` | Target the focused terminal inside a workspace tab. |
| `--workspace <workspace-id>` | Target the focused terminal inside a workspace. |
| `--focused` | Target the terminal that currently receives keyboard input. |

Discovery commands return JSON that scripts can pipe to `jq`:

```bash
omux list --full
omux sessions
omux panes
```

Hooks can explicitly fetch bounded pane history when they need more output context than the hook payload includes:

```bash
pane_id="$(printf '%s' "$payload" | jq -r '.paneID')"
omux history --json "$pane_id"
```

`omux history` without a pane ID reads panes in the active workspace, `omux history <pane-id>` reads one pane/pane-tab, and `omux history all` reads every pane across workspaces and tabs. The command can include bounded per-pane history persisted with workspace state plus current live terminal text when available. The command is read-only: it does not send text to the terminal, mutate pane state, or render history into pane UI. History may contain secrets, so hooks should request it only when needed and avoid writing it to shared logs.

Use `run` when you want OpenMUX to submit a command, and `send-text` when you only want to insert text:

```bash
omux run --pane "$pane_id" -- pnpm dev
omux send-text --session "$session_id" -- "Analysis complete. See logs above."
```

`send-text` does not append Return/Enter. This makes it safe for hooks to write explanatory text into a terminal without executing it.

## Current hook names

### Lifecycle hooks

| Hook | Emitted when | Context | Payload |
| --- | --- | --- | --- |
| `workspace-opened` | A workspace is opened. | `workspaceID`, `sessionID` | `{ "path": string }` |
| `workspace-renamed` | A workspace custom name changes. | `workspaceID` | `{ "name": string }` |
| `workspace-closed` | A workspace is closed. | `workspaceID` | `{ "path": string }` |

### Session and pane hooks

| Hook | Emitted when | Context | Payload |
| --- | --- | --- | --- |
| `pane-focused` | A session/pane is focused. | `workspaceID`, `sessionID` | `{}` |
| `tab-created` | A top-level workspace tab is created. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{}` |
| `pane-created` | A split creates a new pane. | `workspaceID`, `paneID`, `sessionID` | `{}` |
| `pane-tab-created` | A local pane tab is created inside a pane stack. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "paneStackID": string }` |
| `pane-tab-closed` | A local pane tab is closed. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "paneStackID": string \| null }` |
| `pane-removed` | A pane is removed from the workspace layout. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{}` |

### Command hooks

| Hook | Emitted when | Context | Payload |
| --- | --- | --- | --- |
| `command-started` | `omux run` sends a command to a live session. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "command": string, "cwd": string \| null, "outputContext": { "kind": "unavailable" } }` |
| `terminal-command-finished` | The terminal runtime reports a command completion. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "command": string \| null, "cwd": string \| null, "exitCode": integer \| null, "durationNanoseconds": integer \| double, "outputContext": object }` |
| `command-failed` | A command completion reports a nonzero exit code. | `workspaceID`, `tabID`, `paneID`, `sessionID` | Same as `terminal-command-finished`. |

`outputContext` is bounded and explicit. Current values are:

| Shape | Meaning |
| --- | --- |
| `{ "kind": "tail", "tail": string }` | OpenMUX has a bounded tail of OpenMUX-owned terminal output. |
| `{ "kind": "unavailable" }` | No output context is available. Hooks should not assume a transcript exists. |

### UI hooks

| Hook | Emitted when | Context | Payload |
| --- | --- | --- | --- |
| `notification-raised` | OpenMUX raises a notification through the shared notification action. | `workspaceID` when available | `{ "title": string, "body": string, "severity": string }` |
| `terminal-open-url` | The terminal runtime requests that OpenMUX open a URL. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "url": string, "kind": "unknown" \| "text" \| "html" }` |
| `terminal-desktop-notification` | The terminal runtime requests a desktop notification. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "title": string, "body": string \| null }` |
| `terminal-bell` | The terminal runtime reports a bell. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{}` |

### Terminal session hooks

These hooks are emitted from terminal runtime action dispatch after libghostty-specific data has been translated into OpenMUX-native payloads.

| Hook | Emitted when | Context | Payload |
| --- | --- | --- | --- |
| `terminal-cwd-changed` | The terminal runtime reports a current working directory change. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "path": string }` |
| `terminal-title-changed` | The terminal runtime reports a pane title change. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "title": string }` |
| `terminal-tab-title-changed` | The terminal runtime reports a tab title change. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "title": string }` |
| `terminal-progress-reported` | The terminal runtime reports progress state. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "state": "removed" \| "active" \| "error" \| "indeterminate" \| "paused", "progress": integer \| null }` |
| `terminal-child-exited` | The terminal runtime reports child process exit state. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "exitCode": integer, "elapsedMilliseconds": integer \| double }` |
| `terminal-renderer-health-changed` | The terminal runtime reports renderer health. | `workspaceID`, `tabID`, `paneID`, `sessionID` | `{ "isHealthy": boolean }` |

## Boundary rules

Hooks are stable OpenMUX contracts, not implementation leaks:

- hook payloads use OpenMUX-native identifiers and values
- hooks do not receive AppKit view objects
- hooks do not receive libghostty enums or payload structs
- hooks are observational side-effect processes, not an event-stream command bus
- if a hook wants to mutate OpenMUX state, it should call `omux` or the local JSON-RPC control plane explicitly

## Examples

### Bootstrap a workspace layout

This hook creates a default workspace layout when a workspace opens: split down, split the lower pane right, then run `pnpm dev` in the lower-left pane.

Place it at `~/.omux/hooks/workspace-opened/10-bootstrap-layout` and make it executable.

```bash
#!/usr/bin/env bash
set -euo pipefail

event="$(cat)"
workspace_id="$(printf '%s' "$event" | jq -r '.workspaceID')"

lower_pane_id="$(
  omux split --workspace "$workspace_id" down \
    | jq -r '.created.paneID'
)"

# Split the lower pane into left/right panes. The original lower pane remains
# targetable, so run the dev server there after creating the neighbor pane.
omux split --pane "$lower_pane_id" right >/dev/null
omux run --pane "$lower_pane_id" -- pnpm dev >/dev/null
```

### Analyze failed commands with an external agent

This hook listens for failed commands, sends the bounded output context to a local analyzer, then writes the result back to the originating terminal without executing it.

Place it at `~/.omux/hooks/command-failed/20-analyze-failure` and make it executable.

```bash
#!/usr/bin/env bash
set -euo pipefail

event="$(cat)"
session_id="$(printf '%s' "$event" | jq -r '.sessionID')"
command="$(printf '%s' "$event" | jq -r '.payload.command // "<unknown command>"')"
output_tail="$(printf '%s' "$event" | jq -r '.payload.outputContext.tail // ""')"

analysis="$(
  printf 'Command: %s\n\nOutput:\n%s\n' "$command" "$output_tail" \
    | my-local-agent analyze-terminal-failure
)"

omux send-text --session "$session_id" -- "$(printf '\nOpenMUX analysis:\n%s\n' "$analysis")"
```
