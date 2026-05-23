## 1. Workspace Controller Boundary Extraction

- [x] 1.1 Define internal interfaces for workspace state/index management and move pure state logic behind them.
- [x] 1.2 Extract hook/control-plane publication helpers into a dedicated publication seam and route existing event emission through that seam.
- [x] 1.3 Add/expand tests proving behavioral parity for create/focus/split/close/restore controller flows, including stable hook/event payload compatibility.
- [x] 1.4 Document the publication seam as the required attachment point for future open-by-design transition wiring.
- [x] 1.5 Extract one lookup/state slice from `WorkspaceController` and prove indexed target resolution parity against the current workspace scan behavior.

## 2. Incremental Slice Migration

- [x] 2.1 Move one mutation/query slice at a time from `WorkspaceController` into extracted modules with no API behavior change.
- [x] 2.2 Keep terminal bridge boundary intact by enforcing OpenMUX-native types in extracted module contracts.
- [x] 2.3 Add invariant and regression tests for indexed lookup correctness and event payload compatibility.
- [x] 2.4 Verify extracted publication paths do not add new inline hook/control-plane wiring outside the dedicated seam for migrated controller slices.

## 3. Workspace Window Shell Boundary Extraction

- [x] 3.1 Identify the first shell/view-host extraction seam inside `WorkspaceWindowController` and split it into a dedicated shell-owned module without changing behavior.
- [x] 3.2 Extract at least one additional shell subdomain from `WorkspaceWindowController` such as sidebar/canvas composition, floating modal hosting, or pane chrome helpers.
- [x] 3.3 Add or reorganize shell parity tests so extracted shell/view-host slices are validated without relying only on one monolithic app-shell test file.
- [x] 3.4 Verify shell extraction preserves AppKit-first behavior, terminal host continuity, accessibility IDs, and terminal-bridge ownership boundaries.

## 4. CLI Picker Unification

- [x] 4.1 Extract shared terminal picker engine (raw mode lifecycle, rendering, key parsing, filtering).
- [x] 4.2 Rewire theme and plugin picker implementations to the shared engine while preserving command UX semantics.
- [x] 4.3 Decide whether the vault resume choice picker joins the same engine or stays separate with explicit rationale.
- [x] 4.4 Add tests for shared key handling and terminal cleanup on success/cancel/error exits.

## 5. Documentation and Validation

- [x] 5.1 Update developer documentation describing new controller and shell module boundaries and extension points.
- [x] 5.2 Update planning/documentation notes to reference the publication seam as the prerequisite for open-by-design parity follow-up work.
- [x] 5.3 Run existing AppShell/CLI/ControlPlane tests to verify no keyboard/input or control-plane regressions.
