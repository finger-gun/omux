## Context

Ghostty supports ConEmu-style OSC `9;4` progress reports. OpenMUX already maps those terminal actions into `PaneTerminalState.progress`, but the existing UI exposed them as text status rather than compact tab/sidebar chrome. Many terminal agents and long-running CLIs use this terminal-native path, so it should be the primary mechanism.

Hooks and plugins still need a way to mark a pane when no OSC progress report is available. The public surface should stay generic and pane-oriented, not agent-provider-specific.

## Decisions

### Terminal-native progress is the default signal

OSC progress reports from Ghostty drive pane progress state automatically. OpenMUX treats provider hooks as optional complements, not the main detection mechanism.

### Status chrome is subtle and non-identity

Pane progress renders as a small orb before the semantic icon/name in sidebar pane rows and pane tabs. The orb does not replace pane title, project icon, working directory, or terminal content.

State mapping:

- `working` / `active` / `indeterminate`: pulsing orb.
- `error`: static red orb.
- `idle` / done: static blue orb for a short duration, then clear.
- `clear`: remove status immediately.

Pulse animation must respect reduced-motion settings.

### Hooks/plugins use a generic pane-status API

The CLI command is `omux pane-status` with existing terminal selectors: `--session`, `--pane`, `--tab`, `--workspace`, and `--focused`. It calls a provider-neutral `pane.status` JSON-RPC method. Optional `label`, `message`, and `source` fields are included in events for scripts and diagnostics, but v1 chrome remains orb-only.

### Status remains transient

Pane progress/status is runtime UI state. It is not persisted with workspace layout or scrollback, and restored workspaces start without stale running/error/idle indicators.

## Risks / Trade-offs

- Persistent idle indicators would add visual noise, so idle is brief and then clears.
- Provider-specific adapters can still be useful, but shipping them in core would make OpenMUX AI-shaped; examples should call the generic CLI instead.
- Status metadata is event-visible but not rendered as text in v1, keeping pane chrome compact.
