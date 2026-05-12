## 1. Workspace Controller Boundary Extraction

- [ ] 1.1 Define internal interfaces for workspace state/index management and move pure state logic behind them.
- [ ] 1.2 Extract hook/control-plane publication helpers and route existing event emission through them.
- [ ] 1.3 Add/expand tests proving behavioral parity for create/focus/split/close/restore controller flows.

## 2. Incremental Slice Migration

- [ ] 2.1 Move one mutation/query slice at a time from `WorkspaceController` into extracted modules with no API behavior change.
- [ ] 2.2 Keep terminal bridge boundary intact by enforcing OpenMUX-native types in extracted module contracts.
- [ ] 2.3 Add invariant and regression tests for indexed lookup correctness and event payload compatibility.

## 3. CLI Picker Unification

- [ ] 3.1 Extract shared terminal picker engine (raw mode lifecycle, rendering, key parsing, filtering).
- [ ] 3.2 Rewire theme and plugin picker implementations to the shared engine while preserving command UX semantics.
- [ ] 3.3 Add tests for shared key handling and terminal cleanup on success/cancel/error exits.

## 4. Documentation and Validation

- [ ] 4.1 Update developer documentation describing new controller module boundaries and extension points.
- [ ] 4.2 Run existing AppShell/CLI/ControlPlane tests to verify no keyboard/input or control-plane regressions.
