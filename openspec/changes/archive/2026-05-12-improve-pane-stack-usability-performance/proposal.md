## Why

OpenMUX feels sluggish under frequent workspace updates because the app shell rebuilds large portions of the pane UI tree, which also causes avoidable focus and view-state regressions (for example during live preview updates and pane-tab interactions). This is the right time to fix it because pane-stack interactions are now central to day-to-day workflows, and performance, terminal-first ergonomics, and clean extensible structure are core manifesto commitments.

### Goals

- Make pane-stack interactions feel immediate under heavy update frequency.
- Add missing same-stack pane-tab reorder behavior to close a usability gap in drag workflows.
- Replace broad view teardown/rebuild paths with keyed reconciliation so pane and extension hosts preserve stable state (focus, scroll, transient UI state).
- Improve code structure/readability by moving pane update logic toward explicit, testable, composable update boundaries instead of ad-hoc full rerender paths.
- Keep terminal behavior, keyboard correctness, and libghostty boundaries unchanged.

### Non-goals

- No browser-heavy architecture, no background daemons, and no in-process plugin runtime expansion.
- No changes to terminal rendering engine ownership or libghostty type exposure.
- No redesign of pane chrome visuals beyond behavior needed for reorder and update-state correctness.
- No vendor-specific workflows or AI-first coupling in core pane behavior.

## What Changes

- Add same-stack pane-tab reordering via existing drag interaction patterns, including deterministic drop placement rules.
- Introduce keyed workspace canvas reconciliation to reuse existing pane stack and host views when pane identity is unchanged.
- Ensure focus/responder, extension-pane host state, and per-pane transient view state survive non-structural workspace updates.
- Refactor pane rendering/update paths into smaller composable units with explicit ownership boundaries and clearer naming.
- Expand regression coverage for high-frequency update scenarios, drag reorder semantics, and focus/state preservation under mixed terminal/extension panes.
- Document the clean-room approach as OpenMUX-native behavior design (no copied GPL implementation details).

## Capabilities

### New Capabilities

- `workspace-render-reconciliation`: Keyed, identity-preserving workspace render updates that avoid full canvas teardown and preserve pane host state across non-structural changes.

### Modified Capabilities

- `pane-tab-drag-splitting`: Extend drag behavior to support same-stack pane-tab reorder with deterministic insertion and preserved pane/session identity.
- `macos-app-shell`: Update shell requirements so frequent workspace state changes preserve focus and host view continuity rather than rebuilding all pane UI state.
- `extension-content-panes`: Tighten update behavior requirements so extension-pane host state is preserved across routine content/status refreshes.

## Impact

- **Affected code**: `Sources/OmuxAppShell/WorkspaceWindowController.swift`, `WorkspaceCanvasView`, pane stack/header rendering paths, drag/drop intent and drop application paths, and focused update paths in `WorkspaceController`.
- **Tests**: `Tests/OmuxAppShellTests` for drag reorder semantics, render reconciliation behavior, focus preservation, and mixed terminal/extension-pane update stability.
- **APIs/contracts**: Workspace/pane update behavior requirements in existing specs; no intentional breaking public CLI or JSON-RPC command changes.
- **Performance**: Lower view churn, fewer unnecessary allocations/layout passes, less responder-state disruption, improved responsiveness under rapid pane updates.
- **Architecture/guardrails**: Keeps libghostty boundary intact, stays terminal-first, preserves plugin/hook openness, and avoids monolithic core growth.
