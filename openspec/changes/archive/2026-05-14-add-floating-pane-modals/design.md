## Context

OpenMUX already has three important pieces of groundwork for this change:

- extension panes are first-class pane content with shell-owned rendering and stable pane identity
- the command palette proves the AppKit shell can host native overlay UI above the workspace canvas
- pane-tab drag interactions already support reorder, merge, and split movement using OpenMUX-native pane and pane-stack identifiers

What is missing is a coherent floating presentation model. Today a plugin can open extension content only as a docked pane, while the shell already contains overlay-style UI. If floating plugin content becomes a second ad hoc host path, OpenMUX will accumulate inconsistent shell surfaces and make future dock/undock behavior harder. The right direction is to treat modal presentation as another shell-level presentation target for pane content, while keeping rendering in the shell and keeping terminal behavior behind the existing libghostty bridge.

This change is cross-cutting because it touches workspace state, shell rendering, drag/drop behavior, control-plane contracts, plugin settings, and focus/input behavior.

## Goals / Non-Goals

**Goals:**

- Add a reusable shell-owned floating modal presentation for pane content.
- Preserve pane identity when moving extension content between docked layout and floating modal presentation.
- Support a first implementation where Markdown preview opens as either a pane tab or a modal through OpenMUX-native configuration.
- Allow pane-tab drag interactions to snap eligible pane tabs out into a modal and dock eligible floating content back into a pane stack.
- Keep terminal rendering, terminal session ownership, and libghostty types out of modal/layout contracts.
- Keep keyboard and focus behavior explicit so terminal panes, extension panes, IME flow, dead keys, and Option/Alt handling remain correct.

**Non-Goals:**

- Turning OpenMUX into a general browser shell or arbitrary window manager.
- Adding free-form multiple overlapping document windows outside the current workspace window.
- Introducing background services or remote state just to manage floating UI.
- Supporting arbitrary modal splitting trees in the first implementation.
- Reworking command-palette behavior beyond sharing shell overlay infrastructure.

## Decisions

### Decision: Model floating modals as pane presentation, not a second plugin UI system

Floating modals should host OpenMUX pane content rather than a separate modal-only content descriptor. A pane keeps its existing identity and content descriptor while its presentation changes between docked workspace layout and floating modal.

Alternatives considered:

- **Separate modal-only plugin surface:** simpler at first, but duplicates lifecycle, focus, rendering, and drag/dock semantics.
- **Plugin-owned windows:** too far from the current shell architecture and weakens inspectable shell contracts.

This keeps the model OpenMUX-native: panes remain panes, and the shell decides where they are presented.

### Decision: Introduce shell overlay infrastructure that can host both palette and floating modals

The AppKit shell should add a reusable overlay host layer instead of accumulating one-off full-window overlay views. Command palette behavior remains the same, but floating modal containers use the same shell-owned overlay region.

Alternatives considered:

- **Keep adding separate overlay view properties:** expedient, but leads to parallel presentation systems and brittle z-order/focus handling.
- **Use detached macOS windows first:** heavier than needed and makes dock/undock semantics harder to keep tied to workspace state.

This stays native and lightweight while keeping the command palette and plugin modals in one shell-owned presentation lane.

### Decision: Represent floating modals as workspace-owned floating pane stacks

The workspace model should add a floating-modal collection whose unit is a pane stack, not an arbitrary HTML blob. This allows a snapped-out pane tab to become a floating modal without content conversion and leaves room for future multi-tab modal behavior while keeping v1 implementation to a single stack per modal.

Alternatives considered:

- **Single-pane modal model only:** simpler data model, but immediately complicates drag-out/in for existing pane-tab stacks.
- **Full floating split tree:** powerful, but too much scope for the first implementation.

Pane-stack modals align with the current pane-tab system and preserve identity through movement.

### Decision: Keep extension rendering in existing shell-owned pane hosts

Floating modal presentation should reuse the current pane host strategy. Terminal panes still render through `GhosttyTerminalBridge` hosted views; extension panes still render through shell-owned hosts such as `ExtensionPaneHostView`. Modal presentation changes the container, not the renderer.

Alternatives considered:

- **Route floating terminal panes through a new bridge API:** unnecessary leakage of presentation concerns into the terminal bridge.
- **Create a separate WebKit modal host path:** duplicates extension host logic and state continuity.

This protects the terminal bridge boundary and keeps modal behavior in the shell.

### Decision: Extend public extension-pane creation with explicit presentation metadata

Extension-pane creation/update requests should gain an inspectable presentation target so plugins can request docked-pane or floating-modal presentation through the same public control-plane surface. Docked requests may still use split-axis metadata; modal requests use modal presentation metadata instead.

Alternatives considered:

- **Implicit “modal if no axis” behavior:** too ambiguous and hard to inspect.
- **Separate modal-only plugin API:** duplicates extension-pane lifecycle and weakens the stable contract.

This keeps the protocol simple: the same pane contract, one extra presentation choice.

### Decision: First user-facing setting is Markdown preview presentation

The bundled Markdown preview plugin should be the first consumer through a plugin setting such as `presentation = "pane-tab" | "modal"`. The default remains docked pane behavior so existing workflows do not change unexpectedly.

Alternatives considered:

- **Modal-only preview change:** useful demo, but not aligned with the need for user choice.
- **Per-command override only:** flexible, but misses the user’s stated preference for a durable setting.

This gives the first feature immediate value without forcing broader plugin UI changes all at once.

### Decision: Dock/undock stays app-level and identity-preserving

Dragging a pane tab outside the docked canvas into a valid tear-out zone should create a floating modal using the same pane identity. Dragging a floating modal tab/header onto a valid pane-stack target should dock the same pane back into the workspace. Focus should follow the moved pane, and extension host state should remain continuous when the pane identity survives.

Alternatives considered:

- **Close and recreate on dock/undock:** easier implementation, but breaks watch-mode continuity, scroll state, and plugin action context.
- **Limit drag-out to extension panes only forever:** reduces scope but leaves the pane-tab model inconsistent.

Identity-preserving movement matches recent pane-tab drag behavior and keeps modal support composable.

## Risks / Trade-offs

- [Risk] Overlay focus bugs could leak keyboard input to the wrong pane. → Mitigation: keep explicit first-responder management for modal focus, dismissal, and restore paths, with regression coverage for terminal panes, extension panes, IME, and Escape handling.
- [Risk] Workspace state becomes more complex once panes can be docked or floating. → Mitigation: keep presentation state orthogonal to pane content and limit v1 floating layout to pane-stack modals rather than arbitrary floating split trees.
- [Risk] Drag semantics become confusing if modal tear-out and dock-in compete with existing split/merge behavior. → Mitigation: define clear priority rules and start with narrow valid drop zones for tear-out/dock.
- [Risk] Markdown preview setting could accidentally fork plugin behavior from generic extension-pane behavior. → Mitigation: add generic presentation contracts first and layer the Markdown setting on top of them.
- [Risk] Terminal panes in floating modals may expose host-state continuity issues. → Mitigation: implement modal infrastructure generically but scope first shipping behavior to Markdown preview and extension panes before broadening terminal-tab tear-out if needed.

## Migration Plan

1. Add workspace/shell presentation modeling for floating pane modals behind existing pane identities.
2. Add shell overlay host support for floating modal containers while preserving current command palette behavior.
3. Extend extension-pane control-plane contracts with explicit presentation metadata.
4. Add Markdown preview configuration for pane-tab versus modal opening and wire preview creation through the new presentation contract.
5. Extend pane-tab drag handling with tear-out and dock-in paths for eligible content.
6. Persist floating modal presentation with workspace state in the same rollout as modal interaction support, and keep fallback behavior explicit if a plugin is disabled on restore.

Rollback strategy: if modal presentation causes regressions, docked pane behavior remains the stable baseline because pane content and renderers are unchanged; floating presentation can be disabled without removing extension panes entirely.

## Open Questions

- Should initial drag-out support be limited to extension panes, or should terminal pane tabs be allowed to float in the same first implementation?
- What is the smallest inspectable control-plane shape for modal geometry and placement without overdesigning window-management concerns?
