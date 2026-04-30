## Context

`macos-foundation` established the architecture boundaries for OpenMUX, but the current application still behaves like a scaffold: it opens a minimal native window, shows placeholder pane content, and proves the shell, bridge, control-plane, and hook seams exist. The next step is to turn that scaffold into the first real terminal workspace so the product starts validating its core thesis in user interaction rather than only in structure.

The key constraint is that this change must remain faithful to the foundation. The terminal surface must stay AppKit-native, libghostty must remain behind the existing bridge boundary, keyboard/input normalization must remain upstream of terminal dispatch, and the UI shell and `omux` control plane must continue to operate on the same workspace/session model. This is the first product slice, not a redesign of the architecture.

## Goals / Non-Goals

**Goals:**
- Replace placeholder panes with real terminal-backed pane hosting.
- Add the first usable native workspace layout model with tabs, split panes, and focus movement.
- Connect workspace/session actions to both direct UI interaction and the existing `omux` control plane.
- Exercise the normalized input pipeline through real terminal interaction.
- Deliver the first OpenMUX experience that feels like a terminal workspace rather than a shell prototype.

**Non-Goals:**
- Full persistence and restore semantics.
- A polished settings or onboarding experience.
- Full notification/attention design beyond existing basics.
- Rich plugin runtime work, marketplace ideas, or language-specific plugin support.
- Packaging, notarization, or release pipeline work.

## Decisions

### 1. Implement the first usable slice as one vertical workspace path

This change should ship one coherent path: open a workspace, render real terminal panes, create tabs and splits, move focus, and route commands through the same domain model. It should not scatter effort across many partial features.

**Why this decision:** The manifesto’s v1 direction is about proving the foundation through a useful product slice. A vertical path validates the shell, bridge, input model, and control plane together.

**Alternatives considered:**
- **Only terminal hosting first:** validates the bridge, but leaves the shell feeling incomplete.
- **Only tabs/splits first with placeholders:** validates layout, but still does not prove the terminal-first product thesis.

### 2. Keep pane layout and terminal hosting separate but connected

The workspace shell should own tabs, split topology, pane focus, and visual orchestration. The terminal bridge should continue to own the creation and attachment of terminal surfaces and sessions.

**Why this decision:** The foundation already established that libghostty should stay behind a narrow boundary. This change should deepen that separation instead of eroding it when real pane views arrive.

**Alternatives considered:**
- **Let pane views manage terminal state directly:** faster to wire initially, but undermines the bridge boundary and makes future evolution harder.

### 3. Use the same workspace/session actions for UI and control-plane behavior

The first usable action set should be expressed as OpenMUX-native operations such as open workspace, create tab, split pane, focus session, and run command. UI interactions and `omux` commands should both invoke those operations through shared orchestration.

**Why this decision:** The manifesto explicitly frames `omux` as a remote control for the app, not a separate terminal product. The control plane and the UI should therefore operate on the same capabilities instead of diverging.

**Alternatives considered:**
- **Separate UI-only and CLI-only implementations:** simpler to prototype, but produces drift and weakens the control-plane story.

### 4. Make keyboard correctness part of the usable workspace slice

This change should not treat input correctness as “later polish.” Real terminal pane hosting must go through the normalized input pipeline so Option/Alt behavior, dead keys, and focus-dependent shortcuts are exercised in the real shell.

**Why this decision:** Once real terminal panes exist, the input pipeline becomes a visible part of the product. The first usable slice is exactly where keyboard behavior needs to be validated in context.

**Alternatives considered:**
- **Wire direct AppKit key handling into the pane first and normalize later:** faster to prototype, but directly conflicts with the architecture and quality bar.

### 5. Defer persistence and advanced hooks to later follow-on changes

This change should establish a usable runtime workspace, but it should not also absorb persistence, restore policy, or richer hook-trigger behavior beyond what is necessary for the core workflow.

**Why this decision:** The project now needs a real workspace before it needs a complete one. Persistence and richer automation can follow once the live model is proven.

**Alternatives considered:**
- **Bundle persistence into workspace-shell:** tempting because the concepts are related, but likely to broaden the change too much.

## Risks / Trade-offs

- **[Real terminal integration reveals bridge gaps]** → Keep the bridge interface explicit and extend it through OpenMUX-native abstractions rather than bypassing it.
- **[Layout complexity grows too quickly]** → Start with a minimal but useful tabs-and-splits model instead of a fully general workspace graph.
- **[UI and CLI actions drift apart]** → Express all first-phase actions as shared workspace/session operations and have both surfaces call through them.
- **[Keyboard regressions become visible immediately]** → Route pane input through the normalized input pipeline and include explicit validation scenarios around Option/Alt and dead-key behavior.
- **[Scope expands into persistence and polish]** → Keep this change centered on real-time workspace usability, not full v1 completeness.

## Migration Plan

1. Extend the current placeholder pane shell to host real terminal panes via the existing bridge boundary.
2. Introduce the first tabs/splits/focus model in the AppKit shell and bind it to the workspace domain model.
3. Add shared workspace/session actions and expose them through both UI and `omux`.
4. Validate the workspace with live terminal interaction and keyboard-routing scenarios.
5. Use later changes for persistence, richer CLI/control-plane actions, notification hardening, and hook expansion.

## Open Questions

- What is the smallest useful split-pane model that still leaves room for future persistence and restoration?
- Which initial tab and split actions should be exposed through the shell UI versus only through `omux`?
- How much command execution behavior should be modeled as “run command in session” versus plain shell startup configuration in this first slice?
- Do we need a dedicated workspace action service type before implementation, or can the existing controller grow into that role cleanly for one more change?
