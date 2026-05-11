## Why

Pane-local tabs are already part of the terminal workspace model, but moving a tab into a new split currently requires indirect actions instead of direct spatial manipulation. Dragging a pane tab toward an edge to split left, right, up, or down makes layout changes faster and more predictable for terminal-first workflows where developers continuously reorganize shells, editors, logs, and remote sessions.

## Goals

- Allow users to drag a pane-local tab from a pane tab strip and drop it into a split target region.
- Show a clear directional highlight during drag so the user can see whether the tab will split left, right, up, or down before dropping.
- Move the dragged pane tab into the newly created split while preserving terminal session identity and focus behavior.
- Keep split behavior represented through OpenMUX-native workspace, pane stack, and pane tab concepts.
- Keep the interaction native, lightweight, and inspectable without adding browser-heavy UI, background services, or vendor-specific dependencies.

## Non-goals

- This change does not introduce browser or webview-based drag-and-drop infrastructure.
- This change does not change the libghostty bridge contract or expose libghostty-specific layout state.
- This change does not add a plugin API for replacing drag behavior, though it should avoid blocking future hook or action-event integration.
- This change does not change terminal text selection semantics inside the terminal viewport.
- This change does not define cross-window or cross-workspace tab dragging unless explicitly specified later.

## What Changes

- Pane-local tab strips support initiating a drag from a pane tab.
- Workspace layout chrome computes directional split intent from the current drag location relative to eligible pane stack bounds.
- The shell renders a split preview highlight for the intended drop direction: left, right, up, or down.
- Dropping a pane tab onto a valid split region moves that tab into a new split in the highlighted direction.
- Invalid drop locations cancel the drag without changing workspace layout or terminal session state.
- Focus moves to the dropped pane tab after a successful split, following existing workspace focus rules.
- The interaction remains app-level workspace behavior and does not move split-tree ownership into the terminal runtime.

## Capabilities

### New Capabilities

- `pane-tab-drag-splitting`: Defines pane-local tab drag initiation, directional split preview, valid drop behavior, cancellation, focus outcome, and session preservation for drag-to-split interactions.

### Modified Capabilities

- `workspace-layout`: Adds a requirement that workspace split-tree changes can be initiated by directional pane-tab drag drop in addition to existing split actions.
- `pane-tab-stacks`: Adds a requirement that pane-local tabs can be moved out of one pane stack into a newly split pane stack by direct manipulation.
- `pane-chrome-identity`: Adds a requirement that pane chrome renders drag affordance and split-preview feedback without confusing pane tab identity or terminal status chrome.

## Impact

- Affects AppKit shell pane tab strip drag handling, workspace layout hit testing, split preview rendering, and pane-stack move operations.
- Requires shared workspace operations for moving a pane tab into a newly created split so UI behavior remains aligned with automation-friendly action contracts.
- Does not require changes to the libghostty bridge boundary; terminal surfaces remain hosted inside OpenMUX pane models.
- Does not affect keyboard input correctness directly, but implementation must ensure drag handling in pane chrome does not steal focus or text input events from the terminal viewport.
- May later expose action events or hooks for pane-tab move/split outcomes, but this proposal keeps the initial behavior native and minimal.
- Any visual inspiration from existing terminal multiplexers or adjacent tools is clean-room behavioral inspiration only; implementation must remain original and Apache-2.0 compatible.
