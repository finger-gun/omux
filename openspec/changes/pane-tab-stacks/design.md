## Context

OpenMUX now has a workable structure for top-level workspace tabs plus nested split panes, but every split-tree leaf still maps directly to one pane session. That means the current top-level tab bar is carrying two jobs at once: project/workspace navigation and local “I want another context beside this split” behavior.

The user request points at a better interaction model: a split leaf should be able to hold its own small set of pane-local tabs. This is a cross-cutting change because it touches the layout model, focus semantics, shell chrome, shared actions, CLI/control-plane entry points, and restore/persistence assumptions.

The main architectural constraints stay the same:

- the app shell owns layout, focus, and pane-stack structure
- the terminal bridge continues to own only terminal sessions/surfaces
- shared actions must remain available across UI and automation
- keyboard correctness remains blocker-level, especially when focus moves between local tab chrome and terminal content

## Goals / Non-Goals

**Goals:**
- Replace split-tree leaves from “single pane” to “pane stack with one active local tab”.
- Support first-phase local tab operations inside a pane stack: create, focus, close.
- Make split operations act on the active pane tab inside the focused stack.
- Keep the shell UI simple: lightweight local tab strip per pane stack, not a full browser-tab system.
- Extend `omux`/JSON-RPC with pane-stack actions that mirror UI behavior.

**Non-Goals:**
- Drag/drop reorder, moving local pane tabs between stacks, or tear-out tabs.
- Advanced tab-state UI like pinning, previews, badges, or overflow menus.
- Deep persistence/migration beyond preserving coherent in-memory structure for now.
- Any change that leaks pane-stack structure into the terminal bridge.

## Decisions

### 1. Introduce `PaneStack` as the split-tree leaf

The current layout tree uses panes as leaves. The new model should use a `PaneStack` leaf that owns:

- a stable stack identifier
- an ordered list of local pane tabs
- one active local pane tab identifier

Each local pane tab then owns the actual `Pane`/session descriptor.

**Why this approach:** it preserves the current split-tree structure while making local tabs a first-class layout concept instead of a UI-only patch.

**Alternatives considered:**
- **Put tabs directly on `Pane`**: rejected because a pane is already a terminal/session carrier, not a container.
- **Add a second nested split tree just for local tabs**: rejected as too indirect; a stack leaf is simpler and fits the user mental model.

### 2. Keep one focused path through the tree

Focus should remain explicit and predictable:

- workspace has focused top-level tab
- split tree has focused pane stack
- pane stack has focused local pane tab
- local pane tab owns the active terminal session

Shared `focus(sessionID:)` and `focus(paneID:)` logic should resolve through this path.

**Why this approach:** it avoids ambiguous “focused split but different active local tab” state.

### 3. Split operations target the active local pane tab

When the user chooses split right/down, the shell splits the currently active local pane tab inside the focused stack. The original stack location is replaced by a split node whose children include:

- the existing pane stack (keeping its tab history)
- a new pane stack with one new local pane tab

**Why this approach:** it matches the expected mental model from cmux/Ghostty-like workflows: splits happen from what you are currently looking at.

### 4. Start with minimal pane-local tab chrome

The AppKit shell should add a compact local tab strip inside each pane stack:

- tab labels
- active tab indication
- add local tab affordance
- close local tab affordance when more than one exists

No drag/drop or cross-stack movement in this change.

**Why this approach:** it provides the usability gain without overcommitting to a large tab-management system.

### 5. Extend shared actions instead of inventing UI-only behavior

The first pane-stack action set should include:

- create local tab in focused stack
- focus local tab
- close local tab
- split active local tab right/down

These should be accessible in the same shared action layer used by UI and `omux`.

**Why this approach:** it keeps OpenMUX tool-friendly and avoids special cases in the app shell.

## Risks / Trade-offs

- **[Risk] Focus/state complexity increases significantly** → **Mitigation:** keep one explicit focused path and test focus resolution across top-level tabs, pane stacks, and local pane tabs.
- **[Risk] UI update logic becomes harder as nested views gain their own local tab strips** → **Mitigation:** keep layout rendering recursive and model-driven rather than hand-managed ad hoc view mutation.
- **[Risk] Close-tab behavior can become surprising** → **Mitigation:** define simple rules now: closing the active local tab moves focus to an adjacent local tab; closing the last local tab in a stack is disallowed or converts to a no-op depending on the chosen policy.
- **[Risk] Control-plane/API naming could sprawl** → **Mitigation:** use `paneStack.*` capability-oriented operations rather than exposing raw view structure.

## Migration Plan

1. Replace split-tree leaf modeling from `Pane` to `PaneStack` in core layout types.
2. Update workspace focus helpers and shared actions to resolve through pane stacks and local pane tabs.
3. Add minimal pane-stack tab chrome in the AppKit shell.
4. Extend control-plane and CLI actions for create/focus/close local tabs.
5. Add validation coverage and update developer documentation.

Rollback remains straightforward during development because this is still an in-memory model change inside the current module boundaries.

## Open Questions

- Should closing the final local tab in a stack be disallowed, or should it close the whole stack if the parent layout permits it?
- Should new local tabs inherit the current working directory and environment exactly from the active local tab, or only from the workspace root?
- When persistence is added later, should pane-stack-local tabs restore eagerly or lazily?
