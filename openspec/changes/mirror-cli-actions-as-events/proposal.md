## Why

`omux events` currently exposes only a narrow stream of terminal runtime actions, which makes the CLI a poor mirror of the actions OpenMUX actually performs. For a terminal-first, hackable workspace, users and tools need a stable event surface that reflects the same workspace, pane, tab, and session actions available through short `omux` commands and native UI flows.

## Goals

- Make `omux events` reflect user-visible OpenMUX actions rather than only terminal-engine upcalls.
- Establish event coverage for core workspace, tab, pane, pane-tab, focus, and command actions that `omux` can already trigger.
- Keep event names and payloads OpenMUX-native so automation can observe behavior without depending on Ghostty internals.
- Preserve one shared action model so CLI commands, native UI actions, and emitted events describe the same product concepts.

## Non-goals

- Introducing a browser-heavy event system, remote service, or background daemon beyond the existing local control plane.
- Turning arbitrary terminal output such as `ls` text into control-plane events.
- Exposing raw `libghostty` enums, structs, or app-shell ownership callbacks outside the terminal bridge.
- Reproducing cmux implementation details; any parity target is clean-room behavioral inspiration only.

## What Changes

- Expand the streamed `omux events` contract so it publishes OpenMUX-native events for core workspace/session actions, not just terminal action callbacks.
- Define event coverage for the first set of short CLI actions and their native-shell equivalents, including workspace opening, tab creation, pane splitting, pane-tab creation and closing, focus changes, and command injection.
- Specify event naming and payload rules so emitted events can be correlated with the same OpenMUX concepts exposed by CLI commands.
- Clarify the relationship between command surfaces and event surfaces so OpenMUX can evolve toward action/event parity without collapsing product ownership into the terminal engine.
- Keep terminal runtime events and workspace action events distinct but streamable through the same local control-plane subscription surface.

## Capabilities

### New Capabilities
- `control-plane-action-events`: A local event contract for OpenMUX-native workspace and session action events that can be streamed to `omux` clients.

### Modified Capabilities
- `omux-control-plane`: Expand the control plane from terminal-only event publication semantics to a broader streamed event contract covering shared OpenMUX actions.
- `workspace-session-actions`: Require core workspace/session actions to emit corresponding OpenMUX-native events so CLI, UI, and automation observe the same action model.

## Impact

- Affected specs: `openspec/specs/omux-control-plane/spec.md`, `openspec/specs/workspace-session-actions/spec.md`, and a new `openspec/changes/mirror-cli-actions-as-events/specs/control-plane-action-events/spec.md`.
- Affected code will likely include `OmuxCLI`, `OmuxControlPlane`, and `OmuxAppShell` event publication paths in `WorkspaceController` and `OpenMUXControlPlaneService`.
- The change should preserve the `libghostty` bridge boundary, keep keyboard/input behavior unchanged, and remain compatible with hooks and future plugin consumers by using explicit OpenMUX-native payloads.
