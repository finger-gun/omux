## Context

The current app shell and CLI layers contain multi-thousand-line files that mix state mutation, query resolution, event publication, UI orchestration, and utility logic. This coupling slows safe iteration and makes hotspot optimization risky, because unrelated concerns share the same mutation surfaces.

The change is an internal refactor focused on clear boundaries and behavior parity.

## Goals / Non-Goals

**Goals:**
- Reduce controller complexity by extracting focused collaborators with explicit interfaces.
- Keep terminal bridge boundaries and keyboard/input behavior intact.
- Improve testability by isolating pure state logic from side-effect orchestration.

**Non-Goals:**
- Changing control-plane RPC shape or workspace semantics.
- Replacing AppKit shell architecture.
- Introducing new runtime services outside existing process boundaries.

## Decisions

### 1) Extract state/index management from orchestration
- Create a state-focused module responsible for workspace collection, active selection, and indexed lookup maintenance.
- Keep bridge/hook/control-plane side effects in orchestrator-level services.

**Alternative considered:** split by file size only without responsibility boundaries.  
**Why not chosen:** cosmetic splitting would retain coupling and poor test isolation.

### 2) Extract publication concerns
- Introduce dedicated event publication helpers for hook and control-plane events.
- Preserve event payload schema and ordering semantics.

**Alternative considered:** leave event calls inline and rely on style discipline.  
**Why not chosen:** continued duplication and drift risk across large methods.

### 3) Unify CLI terminal picker internals
- Build one shared picker core for keyboard handling, rendering viewport, and search/filter interactions.
- Specialize only item formatting and action semantics per picker (themes/plugins).

**Alternative considered:** keep duplicated picker implementations.  
**Why not chosen:** duplicates bugfix effort and increases behavioral divergence risk.

## Risks / Trade-offs

- **[Risk] Behavior drift during extraction** → **Mitigation:** parity tests for existing controller flows and CLI picker interactions.
- **[Risk] Over-abstraction in early-stage codebase** → **Mitigation:** keep extractions small and aligned with existing concepts (workspace, pane, event).
- **[Risk] Input/keyboard regression from picker unification** → **Mitigation:** preserve key parsing semantics and run existing input/CLI tests.
- **[Risk] Boundary erosion toward terminal bridge** → **Mitigation:** enforce module APIs that accept OpenMUX-native types only.

## Migration Plan

1. Define internal protocols/types for state store, event publisher, and extension-pane coordinator.
2. Move one responsibility slice at a time with green tests after each slice.
3. Extract and switch CLI picker shared engine while preserving existing commands.
4. Remove deprecated internal helpers after parity is established.
5. Rollback strategy: each slice remains independently reversible by module-level rewire.

## Open Questions

- Should state/index modules live under `OmuxAppShell` or move partly into `OmuxCore` later?
- How much debug-only invariant checking should remain in production builds?
