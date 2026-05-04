## Context

Pane-local tabs are already modeled as `PaneStack` entries, rendered by `PaneHeaderView`, and manipulated through shared controller actions (`createPaneTab`, `closePaneTab`, focus, and related context-menu actions). The current header renders pane-tab pills in one group and places the add/close controls in a separate trailing controls group.

This change is a focused native-shell polish pass: keep pane tabs OpenMUX-owned, keep terminal surfaces behind the bridge, and make the pane-tab strip behave like the direct manipulation surface users expect.

## Goals / Non-Goals

**Goals:**
- Render the add-pane-tab control immediately after the last local pane tab in the same tab strip.
- Render a close affordance on each local pane tab when that tab can be closed.
- Route inline controls through existing `WorkspaceController` pane-stack actions.
- Keep pointer hit targets limited to pane chrome so terminal keyboard, IME, Option/right-Option, and selection behavior stay terminal-owned.
- Preserve current CLI, JSON-RPC, shortcut, hook, and persistence contracts.

**Non-Goals:**
- No change to top-level workspace tabs.
- No tab reordering, dragging, detaching, or moving tabs between pane stacks.
- No new control-plane methods or persistence fields.
- No `libghostty` integration changes.

## Decisions

### Decision: Treat the pane-tab strip as the sole home for pane-tab controls

Move the `+` button into the same `tabStrip` stack as pane-tab pills, appended after all local tabs. Remove the separate trailing add/close controls from normal pane-tab creation/close behavior.

**Rationale:** The action creates a sibling of the visible tab pills, so placing it inline communicates scope and reduces scanning. It also preserves terminal area by avoiding extra chrome groups.

**Alternative considered:** Keep the current trailing controls and only add per-tab close buttons. This preserves the current layout but leaves the add action visually detached from the local tab list.

### Decision: Compose each local tab pill from label plus optional close button

Represent each pane-local tab as a small native control containing the tab title and, when close is allowed, an inline `x` hit target for that specific pane tab. Clicking the tab body focuses it; clicking the `x` closes that pane tab.

**Rationale:** Per-tab close maps the action to the exact tab being removed and avoids the ambiguity of a single trailing close button closing the focused tab.

**Alternative considered:** Keep one trailing close button that closes the focused pane tab. This is already available through menus/shortcuts and does not satisfy the requested "on the tabs themselves" behavior.

### Decision: Reuse existing controller actions and close constraints

The inline add button SHALL call the existing pane-stack create action for the current stack. Each inline close button SHALL call the existing close action for its pane ID. Single-tab stacks SHALL not expose an enabled close affordance.

**Rationale:** The model and automation contracts already define close constraints and event behavior. Reusing them keeps UI, shortcut, and CLI semantics aligned.

**Alternative considered:** Add UI-specific close behavior in the view. That would duplicate model rules and risk diverging from CLI/control-plane behavior.

### Decision: Keep pointer-only chrome interaction out of the input pipeline

No new keyboard shortcuts are introduced. Inline controls are native AppKit controls in pane chrome and SHALL not change terminal input routing, compose/dead-key handling, or Option/right-Option semantics.

**Rationale:** Keyboard correctness remains blocker-level; this change is pointer chrome only.

**Alternative considered:** Add hover-only or keyboard-only tab close handling. That would expand input scope without being requested.

## Risks / Trade-offs

- **Risk:** Close buttons may crowd narrow pane headers. -> **Mitigation:** Keep compact sizing and truncate tab labels as needed, preserving terminal content priority.
- **Risk:** Clicks on nested close controls could also trigger tab focus. -> **Mitigation:** Implement distinct hit targets so close invokes only close for that pane tab.
- **Risk:** Single-tab stacks could expose a misleading close button. -> **Mitigation:** Hide or disable close affordances unless the pane stack has more than one local tab.
- **Risk:** UI behavior could diverge from automation. -> **Mitigation:** Route all inline controls through existing controller methods and cover with app-shell tests.
