## 1. Pane-stack core model

- [x] 1.1 Replace split-tree leaves from single panes to pane-stack leaves with active local pane tab state.
- [x] 1.2 Update workspace focus helpers so they resolve top-level tab, pane-stack, and local pane tab focus coherently.
- [x] 1.3 Preserve bridge/session attachment semantics so pane-stack changes do not leak shell structure into `OmuxTerminalBridge`.

## 2. Shared actions and control plane

- [x] 2.1 Add shared pane-stack actions for local tab create, focus, and close in the active stack.
- [x] 2.2 Update split actions so split-right and split-down operate on the active local pane tab inside the focused stack.
- [x] 2.3 Extend JSON-RPC and `omux` to expose the first pane-stack action set without bypassing shared shell behavior.

## 3. App shell UI

- [x] 3.1 Add minimal pane-local tab chrome inside each pane stack in the AppKit shell.
- [x] 3.2 Render nested split layouts whose leaves are pane stacks rather than bare terminal panes.
- [x] 3.3 Keep terminal focus, keyboard routing, and paste behavior correct as users move between pane stacks and local pane tabs.

## 4. Validation and documentation

- [x] 4.1 Add validation coverage for pane-stack focus, local tab creation/switch/close, and nested split behavior.
- [x] 4.2 Add validation coverage for control-plane and CLI pane-stack actions.
- [x] 4.3 Update developer-facing documentation to describe pane stacks as the next shell-structure layer and note the intentionally deferred behaviors.
