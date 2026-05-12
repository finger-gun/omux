## Why

Core runtime logic is concentrated in very large files (`WorkspaceController`, `WorkspaceWindowController`, and related shell/control code), making behavior harder to reason about and increasing regression risk when changing hot paths. We should refactor into smaller, explicit modules to improve maintainability and testability without changing user-visible behavior.

## Goals

- Split oversized controller responsibilities into cohesive modules with explicit contracts.
- Preserve current runtime behavior and architecture boundaries while improving code structure.
- Increase unit-test focus around newly extracted boundaries.

## Non-goals

- No UX redesign or feature expansion.
- No cross-platform or webview/browsers-first direction.
- No broad libghostty bridge leakage into app-level modules.

## What Changes

- Extract workspace-state mutation/query responsibilities from `WorkspaceController` into dedicated state/index modules.
- Extract event/hook publication and extension-pane orchestration responsibilities into focused services.
- Consolidate duplicated interactive picker mechanics in CLI into shared reusable primitives.
- Add tests that lock behavioral parity between pre- and post-refactor flows.

## Capabilities

### New Capabilities
- `workspace-controller-module-boundaries`: Define and enforce modular boundaries for workspace runtime orchestration.
- `behavior-safe-controller-refactors`: Require refactor slices to preserve existing behavior via explicit parity tests.
- `shared-cli-interactive-picker-engine`: Provide a shared terminal picker engine for theme/plugin interactive flows.

### Modified Capabilities
- None.

## Impact

- Affected code: `Sources/OmuxAppShell/WorkspaceController.swift`, `Sources/OmuxAppShell/WorkspaceWindowController.swift`, `Sources/OmuxCLI/OmuxCLI.swift`, related tests in `Tests/*`.
- Public CLI/control-plane semantics remain stable.
- Internal architecture becomes more composable and easier to extend safely.
