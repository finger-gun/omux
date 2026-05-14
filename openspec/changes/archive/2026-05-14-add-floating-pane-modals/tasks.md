## 1. Workspace presentation model

- [x] 1.1 Add workspace-model types for floating pane modals and pane presentation state without leaking libghostty concepts.
- [x] 1.2 Update workspace persistence and restore normalization to preserve floating modal state for eligible panes.
- [x] 1.3 Extend workspace/controller mutations to move panes between docked pane stacks and floating modal presentation while preserving pane identity and focus.

## 2. Shell overlay and modal hosting

- [x] 2.1 Introduce reusable shell overlay hosting so the workspace window can manage both command palette and floating pane modal containers.
- [x] 2.2 Implement floating modal container views that host existing pane renderers for extension content and preserve responder/focus behavior.
- [x] 2.3 Add focused shell tests or regressions for modal focus restore and terminal input isolation, including Escape and text-entry behavior.

## 3. Extension-pane and markdown preview contracts

- [x] 3.1 Extend extension-pane control-plane and CLI contracts with explicit presentation metadata for docked pane versus floating modal creation.
- [x] 3.2 Add Markdown preview configuration for default presentation and thread that choice through click-open and CLI preview flows.
- [x] 3.3 Update Markdown preview creation/reuse logic so previews open in the configured presentation and preserve existing watch/update behavior.

## 4. Drag, polish, and documentation

- [x] 4.1 Extend pane-tab drag interactions with tear-out to floating modal and dock-back-into-stack flows using explicit drop-priority rules.
- [x] 4.2 Add regression coverage for pane identity continuity during dock/undock and for extension-pane/plugin ownership validation after presentation moves.
- [x] 4.3 Update user-facing docs for Markdown preview presentation settings and any new extension-pane presentation contract surface.
