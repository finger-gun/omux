## 1. Core Workspace Model

- [x] 1.1 Add an OpenMUX-native drag split direction type or extend an existing direction type so left, right, up, and down map to split axis and insertion side.
- [x] 1.2 Add `TabLayoutNode` support for moving an existing pane into a new split adjacent to a target pane stack while preserving pane and session identity.
- [x] 1.3 Ensure moving the only pane out of a source stack collapses the empty stack through existing split-tree normalization.
- [x] 1.4 Reject invalid model moves, including missing pane IDs, missing target stack IDs, and drops where the source and target pane stack are the same.
- [x] 1.6 Add `TabLayoutNode` support for merging an existing pane into a different pane stack by appending it to that stack's tab list.
- [x] 1.7 Guard against initiating a layout move when the collapse of the source leaf would produce an invalid duplicate-pane state.
- [x] 1.8 Change split insertion to bubble the new pane up to the nearest ancestor split whose axis matches the drop direction, so drops across a perpendicular parent split produce a full-span column or row rather than a local sub-split.
- [x] 1.9 Add `TabLayoutNode.movePaneToRootSplit` that unconditionally wraps the entire root layout in a new split of the given direction.
- [ ] 1.5 Add core tests for right, down, left, and up insertion, single-tab source collapse, source focus repair, same-stack rejection, and pane/session identity preservation.

## 2. Controller Operation

- [x] 2.1 Add a `WorkspaceController` operation for committing a pane-tab drag split using pane ID, source stack ID, target stack ID, and direction.
- [x] 2.2 Route the controller operation through existing workspace mutation, focus, persistence notification, and change publication paths.
- [x] 2.3 Preserve the existing terminal surface association without calling terminal bridge create, attach, teardown, or libghostty-specific layout APIs for the moved pane.
- [x] 2.6 Add a `WorkspaceController` operation for committing a pane-tab drag merge using pane ID, source stack ID, and target stack ID.
- [x] 2.7 Add a `WorkspaceController` operation for committing a root-level split using pane ID, source stack ID, and direction (no target stack ID needed).
- [ ] 2.4 Include source stack, target stack, direction, pane, tab, workspace, and session identifiers in the committed operation payload where internal events already exist.
- [ ] 2.5 Add controller tests for successful move-and-split, rejected same-stack drop, invalid target drop, focus outcome, and terminal bridge non-recreation.

## 3. AppKit Drag Interaction

- [x] 3.1 Make pane-local tab buttons native drag sources carrying the dragged pane ID and source pane stack ID.
- [x] 3.2 Add layout-level drag destination handling that resolves the hovered pane stack and ignores drops outside eligible workspace layout targets.
- [x] 3.3 Implement edge-distance split intent resolution for left, right, up, and down, including stable behavior near pane centers and split borders.
- [x] 3.4 Commit valid drops through the controller operation and cancel invalid drops without mutating workspace state.
- [x] 3.6 Detect when the cursor enters the tab strip zone of a different pane stack and resolve the drop intent as merge rather than split.
- [x] 3.7 Suppress drag initiation when there is exactly one pane stack with exactly one pane tab (no valid drop target exists).
- [x] 3.8 Add canvas outer-edge drop zones (fixed-width strips along each canvas edge) that resolve to a root-level split intent when the cursor is not in another pane's tab strip.
- [x] 3.9 Enforce drop intent priority: merge (different pane header) > canvas outer-edge root split > pane-level directional split.
- [ ] 3.5 Verify terminal viewport pointer drags still route to terminal selection/input behavior and pane chrome dragging does not steal keyboard focus from active terminal input.

## 4. Split and Merge Preview UI

- [x] 4.1 Add a non-interactive AppKit overlay for directional split preview over the current target pane stack.
- [x] 4.2 Render distinct preview regions for split-left, split-right, split-up, and split-down using the active workspace theme.
- [x] 4.3 Clear the preview when the drag leaves a valid target, is cancelled, is rejected, or completes successfully.
- [x] 4.4 Ensure preview rendering preserves pane tab identity, close/create controls, terminal status chrome, and terminal content visibility.
- [x] 4.6 Render a floating semi-transparent ghost of the dragged pane tab that follows the mouse cursor during drag.
- [x] 4.7 Position the ghost centered on the cursor and update its position on every drag-moved event.
- [x] 4.8 Remove the ghost immediately when the drag ends or is cancelled.
- [x] 4.9 Add a non-interactive full-width tab-strip highlight overlay for merge preview over the target pane stack.
- [x] 4.10 Switch between split preview and merge preview based on the resolved `PaneTabDropIntent` for the current hover position.
- [x] 4.11 Render a full-span canvas-level preview overlay when the drop intent is a root-level split via the outer-edge zone.
- [ ] 4.5 Add UI-level tests or focused view tests for preview target resolution and cleanup after cancel/drop where practical.

## 5. Verification

- [ ] 5.1 Run the relevant Swift test targets for core workspace model and app shell behavior.
- [ ] 5.2 Manually verify dragging a tab right, down, left, and up creates the expected split highlight and final layout.
- [ ] 5.3 Manually verify dragging the only tab from a source stack collapses that source stack after a valid drop.
- [ ] 5.4 Manually verify dropping onto the source stack and outside valid targets leaves layout, focus, and terminal sessions unchanged.
- [ ] 5.5 Manually verify terminal text selection, pointer interaction, and keyboard input still work after pane tab drag attempts.
- [x] 5.6 Manually verify dragging a tab onto another pane's tab strip appends it to that stack and focuses it.
- [x] 5.7 Manually verify a single-tab single-pane tab cannot be dragged (drag is suppressed).
