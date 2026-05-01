## Context

The current shell in `Sources/OmuxAppShell/WorkspaceWindowController.swift` spends a meaningful amount of space and visual emphasis on chrome that is not pulling its weight. The layout today is a fixed-width sidebar plus a main column containing a rounded, bordered top bar and a rounded, bordered canvas. Each pane stack then sits inside another rounded, bordered pane card with a header full of pill-shaped controls. The result is that panes are visually nested inside multiple UI shells instead of feeling like the product surface.

At the same time, the keyboard model is not yet optimized for fast workspace use. `Cmd+N` already creates a workspace, but split actions are on `Cmd+]` and `Cmd+[`, there is no sidebar toggle, and there is no direct keyboard jump to a workspace by number or back to the previous active workspace.

This change is intentionally shell-owned. It should leave the terminal bridge alone, keep AppKit in charge of window and chrome behavior, and route shortcuts through the shell/input seams rather than through terminal-engine concepts.

## Goals / Non-Goals

**Goals:**
- Remove low-value chrome so more of the window is terminal surface.
- Flatten pane/canvas styling so the shell reads as a terminal workspace rather than stacked cards.
- Integrate the native titlebar visually with the shell background.
- Add fast keyboard workspace navigation and better split shortcuts.
- Keep keyboard correctness explicit for shell shortcuts on macOS layouts.

**Non-Goals:**
- A general keybinding editor or user-configurable shortcut system.
- Changes to libghostty rendering or terminal session behavior.
- Reworking workspace semantics beyond ordered switching and previous-active recall.
- A larger settings or preferences UI.

## Decisions

### D1. Remove the persistent top bar and keep theme selection in config

The current `WorkspaceTopBarView` is removed from the in-window shell. Its persistent workspace title/path display is dropped, and theme selection remains config-owned rather than moving into a new always-visible or menu-owned shell control.

- **Why:** the top bar currently consumes vertical space while duplicating information already available elsewhere (window title, sidebar context, current project familiarity). Removing it is the single highest-value space recovery.
- **What replaces it:** the workspace name remains in the window title, the root path no longer gets a dedicated always-visible row, and theme selection is handled through OpenMUX config rather than in-window chrome.
- **Alternative rejected:** keeping a “slimmed down” top bar. That preserves the wrong hierarchy; the better move is to stop using persistent in-content controls for low-frequency shell settings.

### D2. Reduce shell hierarchy to sidebar + content + pane header

The target visual stack is:

1. window/shell background
2. workspace sidebar (when visible)
3. content area
4. pane header as the only persistent pane-local chrome
5. terminal surface

`WorkspaceCanvasView` and `PaneCardView` lose their card-like visual treatment. Rounded corners and borders are removed or materially reduced so that pane surfaces feel embedded directly in the shell rather than boxed inside nested containers.

- **Why:** the terminal is the product surface, so the chrome hierarchy should be minimal and structural.
- **Alternative rejected:** keeping the same hierarchy and only softening colors. That would still waste space and preserve the “cards inside cards” feel.

### D3. Keep pane headers and pane actions, but flatten them hard

The pane header remains because pane-local tabs and pane actions still need an anchor, and the add/close pane-tab actions remain visible for now. Its styling becomes much flatter and less ornamental. The current pill-heavy control language is reduced toward simpler segmented/tab-like affordances with less radius, less border emphasis, less padding, and less contrast.

- **Why:** removing all pane header structure would hide useful navigation and pane identity, especially with local pane tabs, and hiding add/close actions now would hurt discoverability during this early product phase.
- **Alternative rejected:** removing pane headers entirely. That would trade one problem (too much chrome) for another (missing orientation and local navigation affordance).

### D4. Make sidebar visibility a first-class persisted OpenMUX state

The workspace column becomes collapsible and expands the content area when hidden. The visibility state is OpenMUX-owned UI state and persists across app restarts. This change does not add a config key for sidebar visibility; the remembered app state is the only source of truth.

- **Shortcut:** `Cmd+B`
- **Behavior:** toggle between fixed-width visible sidebar and fully collapsed sidebar.
- **Why persisted/global:** sidebar visibility is shell presentation state that should feel stable for the user rather than resetting every launch.
- **Why not config-backed right now:** a runtime UI toggle should not force config writes, and this change does not need two competing sources of truth for one simple shell preference.
- **Alternative rejected:** keeping it session-local per window. That would make the shell feel inconsistent and throw away an intentional user preference.

### D5. Workspace number jumps use visible sidebar order; `Cmd+0` is previous-active

Workspace shortcuts use the visible workspace list order already shown in the sidebar and returned from `WorkspaceController.listWorkspaces()`.

- `Cmd+1` through `Cmd+9` select workspaces in visible order
- `Cmd+0` returns to the previous active workspace

The shell maintains a small previous-active workspace tracker so `Cmd+0` behaves like a local MRU toggle.

- **Why:** visible order is predictable and already matches the mental model exposed in the UI.
- **Alternative rejected:** MRU-based numbering. It is harder to learn because the number mapping constantly changes.

### D6. Split shortcuts become shell-first commands

Split actions move to:

- `Cmd+D` → split right
- `Cmd+Shift+D` → split down

These remain AppKit shell commands routed through shared workspace actions, not terminal input.

- **Why:** they are faster to reach and match the keyboard-first direction of the shell.
- **Alternative rejected:** retaining bracket-based defaults. They are less discoverable and less mnemonic for the intended workflow.

### D7. Titlebar integration uses AppKit window configuration, not fake in-content chrome

The window adopts a more unified shell surface through AppKit window styling: full-size content view, transparent titlebar treatment, hidden or deemphasized title text, and shell background color extending through the titlebar region.

- **Why:** the visual problem is the system titlebar reading as a separate white strip above the shell.
- **Why this approach:** it solves the issue at the real ownership boundary (the window) instead of trying to imitate titlebar integration with more in-content UI.
- **Alternative rejected:** adding a fake top strip under the titlebar to color-match it. That would reintroduce the extra band we are trying to remove.

### D8. Shortcut handling remains explicit about keyboard correctness

The shortcut additions remain shell-owned AppKit commands and must coexist with the input pipeline's guarantees for ISO/EU layouts, Option behavior, and focused terminal panes.

- `Cmd`-based shortcuts should invoke shell behavior without inserting terminal text.
- Plain text input and Option/Alt combinations should continue reaching the terminal correctly when not part of a shell command.

- **Why:** this project treats international keyboard correctness as a blocker-level concern, and shell shortcuts are part of that contract.

## Risks / Trade-offs

- **[Theme switching becomes less discoverable in the shell]** → Keep theme ownership in config and document that clearly rather than reintroducing permanent UI chrome.
- **[Less chrome can reduce discoverability]** → Keep pane headers and sidebar selection state as the primary orientation aids.
- **[Sidebar toggle introduces persisted shell state]** → Keep it as a single OpenMUX-owned remembered value so startup behavior stays predictable without adding config precedence rules.
- **[Workspace numbering can become ambiguous if ordering changes]** → Tie numbering to visible sidebar order and keep that order stable unless the user explicitly changes the workspace set.
- **[Shortcut changes can conflict with typing expectations]** → Validate `Cmd`-based routing against focused panes and ISO/EU layout behavior.

## Migration Plan

1. Remove the in-window top bar and rely on config-owned theme selection instead of replacement shell controls.
2. Simplify canvas and pane container styling so the shell hierarchy is flatter.
3. Add persisted OpenMUX-owned sidebar visibility state and `Cmd+B` toggle behavior.
4. Add workspace ordered-jump and previous-active actions in the workspace controller and wire them to menu shortcuts.
5. Remap split shortcuts to `Cmd+D` and `Cmd+Shift+D`.
6. Update AppKit window configuration so the titlebar blends with the shell.
7. Add shortcut and shell-state tests/documentation updates.

Rollback is straightforward during development: restore the existing top bar, fixed sidebar, and key equivalents. No released compatibility migration is required.

## Open Questions
