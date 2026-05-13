## 1. Persistence Coalescing

- [x] 1.1 Add a workspace persistence coordinator that coalesces `onChange`-driven layout saves with an explicit flush API.
- [x] 1.2 Wire `OpenMUXAppDelegate` workspace-change handling through the coordinator while preserving termination/power-off flush behavior.
- [x] 1.3 Add tests for burst-update coalescing, latest-state persistence, and explicit lifecycle flush guarantees.

## 2. Control Plane Event Queue Efficiency

- [x] 2.1 Replace terminal event subscription queue internals with an efficient FIFO implementation (deque/ring-buffer semantics).
- [x] 2.2 Keep publish ordering and cancellation semantics unchanged; update service internals accordingly.
- [x] 2.3 Add tests covering event ordering, sustained stream handling, and post-cancellation non-delivery.

## 3. Workspace Lookup Indexes

- [x] 3.1 Introduce pane/session lookup index structures in `WorkspaceController` and define update hooks for state mutations.
- [x] 3.2 Migrate high-frequency target-resolution call sites to indexed lookup with safe fallback assertions in tests/debug builds.
- [x] 3.3 Add invariant tests that compare indexed vs scan-based resolution across create/move/remove/restore workflows.

## 4. Validation and Docs

- [x] 4.1 Run existing AppShell/ControlPlane/Core test suites and verify no keyboard/input-path regressions.
- [x] 4.2 Update relevant development documentation to capture new persistence and lookup invariants for contributors.
