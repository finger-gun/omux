## Why

Core runtime logic is concentrated in very large files (`WorkspaceController`, `WorkspaceWindowController`, and related shell/control code), making behavior harder to reason about and increasing regression risk when changing hot paths. We should refactor into smaller, explicit modules to improve maintainability and testability without changing user-visible behavior.

## Goals

- Split oversized controller responsibilities into cohesive modules with explicit contracts.
- Preserve current runtime behavior and architecture boundaries while improving code structure.
- Increase unit-test focus around newly extracted boundaries.
- Establish a dedicated hook/control-plane publication seam so future open-by-design coverage work lands on focused collaborators instead of adding more inline wiring inside `WorkspaceController`.
- Reduce the blast radius of app-shell and CLI changes by separating controller-state work, shell/view-host work, and CLI picker work into explicit slices inside one coordinated refactor.

## Non-goals

- No UX redesign or feature expansion.
- No attempt to close all open-by-design coverage gaps inside this refactor.
- No cross-platform or webview/browsers-first direction.
- No broad libghostty bridge leakage into app-level modules.

## What Changes

- Extract workspace-state mutation/query responsibilities from `WorkspaceController` into dedicated state/index modules.
- Extract event/hook publication and extension-pane orchestration responsibilities into focused services.
- Preserve and clarify the publication path that owns hook invocation and control-plane event emission so later parity work can add missing surfaces without re-entangling controller mutation paths.
- Extract shell/view-host responsibilities from `WorkspaceWindowController` into smaller shell-owned view and composition modules without changing AppKit-first behavior.
- Consolidate duplicated interactive picker mechanics in CLI into shared reusable primitives.
- Break the refactor into explicit sub-scopes with targeted parity tests so controller, shell, and CLI extraction can land incrementally.
- Add tests that lock behavioral parity between pre- and post-refactor flows.

## Capabilities

### New Capabilities
- `workspace-controller-module-boundaries`: Define and enforce modular boundaries for workspace runtime orchestration.
- `workspace-window-shell-boundaries`: Define and enforce modular boundaries for shell-owned workspace window, canvas, sidebar, floating modal, and pane-host composition.
- `behavior-safe-controller-refactors`: Require refactor slices to preserve existing behavior via explicit parity tests.
- `shared-cli-interactive-picker-engine`: Provide a shared terminal picker engine for theme/plugin interactive flows.

### Modified Capabilities
- None.

## Impact

- Affected code: `Sources/OmuxAppShell/WorkspaceController.swift`, `Sources/OmuxAppShell/WorkspaceWindowController.swift`, `Sources/OmuxCLI/OmuxCLI.swift`, related tests in `Tests/*`.
- Public CLI/control-plane semantics remain stable.
- Existing hook and control-plane event payloads remain stable while their publication path becomes a clearer internal boundary.
- App-shell view composition remains AppKit-first and terminal-bridge-safe while internal shell/view boundaries become more explicit.
- Internal architecture becomes more composable and easier to extend safely.
