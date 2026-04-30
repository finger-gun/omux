## Why

OpenMUX now has a solid architectural foundation, but the app is still only a minimal shell with placeholder pane content. The next step is to turn that foundation into the first usable terminal workspace so the project can validate its terminal-first, native-macOS, and hackable design in real interaction instead of just architecture.

This change matters now because the manifesto and research are clear that v1 should prove native workspaces, libghostty-backed terminal surfaces, tabs, split panes, and focused session control. Without that slice, OpenMUX cannot yet demonstrate the product thesis it is built around.

## Goals

- Turn the current shell into the first genuinely usable OpenMUX workspace.
- Replace placeholder pane rendering with real terminal-backed pane hosting.
- Add native workspace structure with tabs, split panes, and focus transitions.
- Connect workspace/session actions to the existing shell, bridge, and control-plane foundations.
- Exercise the input pipeline through real terminal interaction while preserving keyboard correctness requirements.

## Non-goals

- Full persistence, restore, and recovery behavior.
- A full plugin SDK or richer runtime system.
- Packaging, notarization, or release/distribution work.
- Vendor-specific AI workflows or browser-heavy UI.
- Copying code or implementation details from cmux or other GPL projects.

## What Changes

- Replace the placeholder pane presentation with real libghostty-backed terminal pane hosting through the existing bridge boundary.
- Add native tab and split-pane workspace interactions in the AppKit shell.
- Define the first usable workspace/session action set for opening workspaces, creating tabs, splitting panes, focusing sessions, and running shell commands.
- Connect the UI shell and `omux` control plane to the same workspace/session model so automation and direct interaction stay aligned.
- Exercise the normalized keyboard/input pipeline through terminal-backed panes instead of placeholder views.
- Keep all work within the existing clean-room, AppKit-first, thin-bridge architecture.

## Capabilities

### New Capabilities
- `terminal-pane-hosting`: Real libghostty-backed terminal pane views and surface/session attachment inside the native shell.
- `workspace-layout`: Native tabs, split panes, and focus behavior for the first usable OpenMUX workspace model.
- `workspace-session-actions`: User-facing and CLI-facing workspace/session actions such as open, split, focus, and run-command.

### Modified Capabilities

None.

## Impact

- Affects the AppKit shell, terminal bridge integration, workspace/session orchestration, and `omux` control behavior.
- Turns the current minimal window into the first usable product slice.
- Increases the importance of keyboard/input correctness because real terminal interaction will now depend on it.
- Creates the base that later persistence, notifications, richer CLI features, and hook hardening will build on.
