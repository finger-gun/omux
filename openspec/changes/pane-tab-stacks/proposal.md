## Why

OpenMUX now supports nested split layouts, but each split leaf can host only one pane session. That makes the current top-level tab strip do double duty as both project tabs and local working contexts, which blocks a more natural workflow where each split region can maintain its own small tab stack.

## Goals

- Allow each split leaf to host multiple local pane tabs while keeping one active tab visible at a time.
- Preserve the current split-first interaction model so users can split a layout and then add or switch local tabs inside any split region.
- Keep local pane-tab behavior available through the same app-shell and control-plane action model as the existing workspace actions.
- Maintain the bridge boundary so pane stacks are shell-level structure and the terminal bridge still owns only terminal sessions and surfaces.

## Non-goals

- Cross-window drag and drop of pane tabs or arbitrary movement of pane tabs between stacks.
- A full browser-style tab management system with previews, pinned tabs, or complex overflow behavior.
- Replacing the existing top-level workspace tabs; pane-local tabs are an additional layer, not a removal of workspace tabs.
- Introducing any browser-heavy UI, background service, or vendor-specific workflow.

## What Changes

- Add a pane-stack model so split-tree leaves can hold local pane tabs instead of only a single pane session.
- Introduce first-phase local tab actions for create, focus, and close within the active pane stack.
- Update nested split layout behavior so splitting acts on the active pane tab inside the focused stack.
- Add pane-local tab chrome to the AppKit shell and keep focus/session behavior coherent between workspace tabs, split panes, and local pane tabs.
- Extend `omux` and JSON-RPC so automation can target the same pane-stack operations used by the native shell.

## Capabilities

### New Capabilities
- `pane-tab-stacks`: Pane-local tab stacks for split regions, including active local tab behavior and the first shared pane-stack action set.

### Modified Capabilities
- `workspace-layout`: Workspace layout requirements expand from split-tree leaves as panes to split-tree leaves as pane stacks with active local tabs.
- `workspace-session-actions`: Shared workspace/session actions expand to cover pane-stack-local tab creation, focus, and close actions.
- `macos-app-shell`: The native shell requirements expand to include pane-local tab chrome and focus ownership across workspace tabs, split regions, and local pane tabs.

## Impact

- Affected code: `OmuxCore`, `OmuxAppShell`, `OmuxControlPlane`, `OmuxCLI`, and related tests/docs.
- Affected UX: split regions gain local tabs, focus becomes two-level within a workspace tab, and split actions target the active local pane tab.
- Affected architecture: workspace layout becomes a richer app-level structure while terminal bridge ownership stays unchanged.
- Affected automation: `omux` and JSON-RPC gain new pane-stack actions to keep tool-driven behavior aligned with the native shell.
