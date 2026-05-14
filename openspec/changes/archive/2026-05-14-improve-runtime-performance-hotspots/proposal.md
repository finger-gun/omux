## Why

OpenMUX currently performs several synchronous and repeated operations on hot paths (workspace change, terminal event fan-out, pane lookup), which risks UI latency spikes as workspace size and event volume grow. We need targeted performance work now to preserve terminal responsiveness and keep architecture boundaries clean while the codebase is still easy to reshape safely.

## Goals

- Reduce avoidable main-thread and per-event overhead in persistence and event delivery paths.
- Improve lookup efficiency for pane/session targeting without changing user-visible behavior.
- Keep changes incremental, testable, and bounded to existing architecture contracts.

## Non-goals

- No product-surface redesigns.
- No browser-heavy, daemon-heavy, or vendor-locked architecture changes.
- No expansion of libghostty types beyond the existing terminal bridge boundary.

## What Changes

- Add coalesced and non-blocking workspace persistence behavior for high-frequency update paths.
- Add efficient terminal-event subscription queue behavior with deterministic ordering and reduced per-event cost.
- Add indexed workspace lookup behavior for pane/session resolution to avoid repeated full-tree scans.
- Add explicit regression tests and micro-benchmark-style invariants for the affected paths.

## Capabilities

### New Capabilities
- `workspace-state-write-coalescing`: Coalesce and schedule workspace persistence writes to avoid synchronous hot-path I/O.
- `control-plane-event-queue-efficiency`: Deliver control-plane terminal events with queue semantics that remain efficient under sustained event streams.
- `workspace-lookup-indexes`: Maintain controller-owned lookup indexes for pane/session targeting and updates.

### Modified Capabilities
- None.

## Impact

- Affected code: `Sources/OmuxAppShell/*Persistence*`, `Sources/OmuxAppShell/OpenMUXAppDelegate.swift`, `Sources/OmuxAppShell/WorkspaceController.swift`, `Sources/OmuxAppShell/OpenMUXControlPlaneService.swift`.
- Affected tests: App shell/controller/control-plane tests around persistence, event delivery, and target resolution.
- No API-breaking CLI/RPC changes expected; behavior must remain backward-compatible.
