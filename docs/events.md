# Events

`omux events` streams OpenMUX-native JSON events.

This page is the user-facing reference for event names and payload shape. For hook names and hook payloads, see [Hooks](./hooks.md).

## Event envelope

Each event arrives as a JSON object:

```json
{
  "name": "workspace.opened",
  "workspaceID": "workspace-...",
  "tabID": "tab-...",
  "paneID": "pane-...",
  "sessionID": "session-...",
  "payload": {}
}
```

Common fields:

- `name`: Event name.
- `workspaceID`, `tabID`, `paneID`, `sessionID`: Context identifiers when available, otherwise `null`.
- `payload`: Event-specific OpenMUX-native object.

## Terminal runtime events (`terminal.*`)

These are emitted from terminal runtime callbacks after OpenMUX translates runtime data into OpenMUX-native values.

| Event | Emitted when | Payload (summary) |
| --- | --- | --- |
| `terminal.cwdChanged` | A pane's working directory changes. | `{ "path": string }` |
| `terminal.titleChanged` | A pane title changes. | `{ "title": string }` |
| `terminal.tabTitleChanged` | A tab title changes. | `{ "title": string }` |
| `terminal.openURL` | Terminal requests URL open. | `{ "url": string, "kind": "unknown" \| "text" \| "html" }` |
| `terminal.desktopNotification` | Terminal requests desktop notification. | `{ "title": string, "body": string \| null }` |
| `terminal.bell` | Terminal reports bell. | `{}` |
| `terminal.inputSent` | OpenMUX successfully delivers explicit input (`run`, `send-text`, etc.). | `{ "text": string \| null, "key": string \| null, "keyCode": integer \| null, "modifiers": integer, "route": string \| null, "source": string }` |
| `terminal.textActivated` | User intentionally activates terminal text (for example Command-click). | `{ "token": string, "row": integer, "column": integer, "cwd": string \| null, "resolvedPath": string \| null, "modifiers": integer }` |
| `terminal.commandFinished` | Runtime reports command completion. | `{ "exitCode": integer \| null, "durationNanoseconds": integer \| double, "command": string \| null, "cwd": string \| null, "outputContext": object }` |
| `terminal.progressReported` | Runtime reports progress state. | `{ "state": "removed" \| "active" \| "error" \| "indeterminate" \| "paused", "progress": integer \| null }` |
| `terminal.childExited` | Runtime reports child process exit. | `{ "exitCode": integer, "elapsedMilliseconds": integer \| double }` |
| `terminal.rendererHealthChanged` | Runtime reports renderer health. | `{ "isHealthy": boolean }` |

## Shared action events

These are success-shaped events emitted for completed OpenMUX actions.

| Event | Emitted when | Payload (summary) |
| --- | --- | --- |
| `workspace.opened` | A workspace opens successfully. | `{ "path": string }` |
| `workspace.closed` | A workspace closes successfully. | `{ "path": string }` |
| `workspace.restored` | A workspace is restored successfully. | `{ "path": string }` |
| `tab.created` | A top-level workspace tab is created. | `{}` |
| `pane.split` | A split creates a pane. | `{ "axis": "columns" \| "rows" }` |
| `pane.removed` | A pane is removed from layout successfully. | `{ "paneStackID": string \| null }` |
| `paneTab.created` | A pane tab is created successfully. | `{ "paneStackID": string }` |
| `paneTab.focused` | Pane tab focus changes successfully. | `{}` |
| `paneTab.closed` | A pane tab is closed successfully. | `{ "paneStackID": string \| null }` |
| `session.focused` | Session focus changes successfully. | `{}` |
| `pane.aliasSet` | Pane alias is set successfully. | `{ "alias": string }` |
| `pane.aliasCleared` | Pane alias is cleared successfully. | `{}` |
| `pane.statusChanged` | Pane status is set/changed/cleared successfully. | `{ "state": string, "value": integer \| null, "label": string \| null, "message": string \| null, "source": string }` |
| `command.started` | `omux run` starts a command successfully. | `{ "command": string, "cwd": string \| null, "outputContext": { "kind": "unavailable" } }` |
| `notification.raised` | Notification action succeeds. | `{ "title": string, "body": string, "severity": string }` |
| `config.reloaded` | Config apply/reload completes successfully. | `{ "source": string, "applied": boolean }` |
| `extensionPane.created` | Extension pane is created successfully. | `{ "pluginID": string, "contentKind": string, "source": string \| null }` |
| `extensionPane.updated` | Extension pane is updated successfully. | `{ "pluginID": string, "contentKind": string, "source": string \| null }` |
| `extensionPane.closed` | Extension pane is closed successfully. | `{ "pluginID": string, "paneStackID": string \| null }` |

## Notes

- Events are observational. They are not a command bus.
- Action events are emitted for successful outcomes, not failed attempts.
- Event names are OpenMUX-native and versioned with the codebase.
