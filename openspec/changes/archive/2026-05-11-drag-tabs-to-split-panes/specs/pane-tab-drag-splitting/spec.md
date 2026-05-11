## ADDED Requirements

### Requirement: A floating tab ghost SHALL follow the mouse during drag
During a pane-tab drag, the system SHALL render a floating ghost of the dragged tab that tracks the mouse pointer throughout the drag gesture.

#### Scenario: Ghost appears when drag starts
- **WHEN** the user begins dragging a pane-local tab
- **THEN** OpenMUX SHALL render a semi-transparent ghost of that tab positioned at the cursor

#### Scenario: Ghost tracks the mouse pointer
- **WHEN** the user moves the mouse during a pane-tab drag
- **THEN** the ghost SHALL reposition to remain centered on the cursor throughout the drag

#### Scenario: Ghost is removed when drag ends
- **WHEN** the pane-tab drag is completed or cancelled
- **THEN** OpenMUX SHALL remove the ghost immediately

### Requirement: Pane tabs SHALL be draggable split sources
The system SHALL allow pane-local tabs in pane chrome to initiate a native drag-to-split interaction without changing terminal viewport pointer or text-input behavior.

#### Scenario: User starts dragging a pane tab
- **WHEN** the user begins dragging a pane-local tab from a pane tab strip
- **THEN** OpenMUX starts a pane-tab drag interaction for that pane tab while leaving the terminal viewport input pipeline unchanged

#### Scenario: Terminal viewport drag remains terminal input
- **WHEN** the user drags inside the terminal viewport rather than pane tab chrome
- **THEN** OpenMUX SHALL continue routing the drag through existing terminal pointer and selection behavior

### Requirement: Drag hover SHALL resolve directional split intent
The system SHALL resolve a drag hover over an eligible pane stack to one of four split directions: left, right, up, or down.

#### Scenario: Hover near the right edge previews split right
- **WHEN** the user drags a pane tab over the right edge region of an eligible pane stack
- **THEN** OpenMUX SHALL resolve the split intent as right

#### Scenario: Hover near the lower edge previews split down
- **WHEN** the user drags a pane tab over the lower edge region of an eligible pane stack
- **THEN** OpenMUX SHALL resolve the split intent as down

#### Scenario: Hover near the left edge previews split left
- **WHEN** the user drags a pane tab over the left edge region of an eligible pane stack
- **THEN** OpenMUX SHALL resolve the split intent as left

#### Scenario: Hover near the upper edge previews split up
- **WHEN** the user drags a pane tab over the upper edge region of an eligible pane stack
- **THEN** OpenMUX SHALL resolve the split intent as up

### Requirement: The workspace canvas SHALL expose outer-edge drop zones for full-span splits
The system SHALL define a fixed-width strip along each edge of the entire workspace canvas. Dropping a pane tab in one of these strips SHALL always insert the new pane as a direct sibling of the entire root layout, regardless of which individual pane is under the cursor.

#### Scenario: Hovering in the canvas top strip shows full-width preview
- **WHEN** the user drags a pane tab into the top outer-edge strip of the canvas
- **THEN** OpenMUX SHALL highlight the full width of the canvas top edge to indicate the pane will be inserted above the entire layout

#### Scenario: Hovering in the canvas bottom strip shows full-width preview
- **WHEN** the user drags a pane tab into the bottom outer-edge strip of the canvas
- **THEN** OpenMUX SHALL highlight the full width of the canvas bottom edge to indicate the pane will be inserted below the entire layout

#### Scenario: Drop in canvas outer-edge strip wraps root layout
- **WHEN** the user drops a pane tab while the canvas outer-edge preview is visible
- **THEN** OpenMUX SHALL wrap the entire root layout in a new split, placing the dropped pane before or after the root based on the indicated direction

#### Scenario: Merge intent takes priority over outer-edge zone
- **WHEN** the cursor is both within the canvas outer-edge strip and over the tab strip of a different pane stack
- **THEN** OpenMUX SHALL resolve the intent as merge into that pane stack, not as a root-level split

### Requirement: Drop intent resolution SHALL follow a defined priority order
The system SHALL resolve the active drop intent according to a fixed priority: merge into a different pane stack tab strip first, then canvas outer-edge root split, then pane-level directional split.

#### Scenario: Header zone of a different pane always resolves to merge
- **WHEN** the cursor is in the tab strip of a pane stack other than the drag source
- **THEN** OpenMUX SHALL resolve the intent as merge regardless of the cursor's position relative to canvas edges or split regions

#### Scenario: Outer-edge zone resolves to root split when not in another pane header
- **WHEN** the cursor is in the canvas outer-edge strip but NOT in the tab strip of a different pane stack
- **THEN** OpenMUX SHALL resolve the intent as a root-level directional split

### Requirement: Drag hover SHALL show split preview feedback
The system SHALL render a non-interactive split preview highlight for the currently resolved target pane stack and split direction.

#### Scenario: Valid hover shows directional preview
- **WHEN** a pane-tab drag is hovering over a valid target pane stack with a resolved direction
- **THEN** OpenMUX SHALL show a highlight indicating the region that will be occupied after drop

#### Scenario: Invalid hover clears preview
- **WHEN** a pane-tab drag is hovering over an invalid drop target
- **THEN** OpenMUX SHALL show no split preview and SHALL leave workspace layout unchanged

### Requirement: Dropping a pane tab SHALL move it into the highlighted split
The system SHALL move the dragged pane tab into a newly created pane stack split in the highlighted direction when the user drops on a valid target.

#### Scenario: Drop right creates right split
- **WHEN** the user drops a dragged pane tab while the target preview indicates right
- **THEN** OpenMUX SHALL move the pane tab into a new pane stack to the right of the target pane stack

#### Scenario: Drop down creates lower split
- **WHEN** the user drops a dragged pane tab while the target preview indicates down
- **THEN** OpenMUX SHALL move the pane tab into a new pane stack below the target pane stack

#### Scenario: Drop preserves terminal session identity
- **WHEN** a pane tab is moved by drag-to-split
- **THEN** OpenMUX SHALL preserve the pane ID, session ID, terminal surface association, title, and terminal state for the moved pane tab

#### Scenario: Drop focuses moved pane tab
- **WHEN** a pane tab is successfully moved into a new split by drag-to-split
- **THEN** OpenMUX SHALL focus the moved pane tab in its new pane stack

### Requirement: Split insertion SHALL resolve at the correct layout tree level
When inserting a new pane in a given direction, the system SHALL insert it as a sibling in the nearest ancestor split whose axis matches the drop direction, rather than always splitting at the individual pane level. If no such ancestor exists, the system SHALL wrap the entire root layout in a new split.

#### Scenario: Right drop on a pane inside a vertical stack creates a full-height column
- **WHEN** the user drops a pane tab to the right of a pane that is part of a vertically-stacked split group (rows axis)
- **THEN** OpenMUX SHALL insert the new pane as a new column to the right of the entire vertical group, not only to the right of the individual target pane

#### Scenario: Down drop on a pane inside a horizontal stack creates a full-width row
- **WHEN** the user drops a pane tab below a pane that is part of a horizontally-arranged split group (columns axis)
- **THEN** OpenMUX SHALL insert the new pane as a new row below the entire horizontal group, not only below the individual target pane

#### Scenario: Drop direction matching the ancestor split axis inserts as a sibling in that split
- **WHEN** the user drops a pane tab in a direction whose axis matches an ancestor split node
- **THEN** OpenMUX SHALL insert the new pane as a direct child sibling of that ancestor split, at the position adjacent to the subtree containing the target pane

#### Scenario: No matching ancestor wraps the entire layout
- **WHEN** no ancestor split has an axis matching the drop direction
- **THEN** OpenMUX SHALL wrap the entire root layout in a new split of the drop axis, with the new pane inserted before or after based on the drop direction

### Requirement: Invalid drops SHALL be inert
The system SHALL cancel invalid pane-tab drag drops without mutating workspace layout, pane stacks, focus, or terminal session state.

#### Scenario: Drop outside eligible layout is inert
- **WHEN** the user drops a dragged pane tab outside an eligible pane stack target
- **THEN** OpenMUX SHALL leave the workspace layout and focused pane tab unchanged

#### Scenario: Drop onto source stack is rejected
- **WHEN** the user drops a dragged pane tab onto the same pane stack it came from
- **THEN** OpenMUX SHALL reject the drop and leave the workspace layout unchanged

### Requirement: Drag SHALL be suppressed when it cannot produce a valid drop
The system SHALL not initiate a pane-tab drag interaction when the current layout offers no valid drop target.

#### Scenario: Single-tab single-pane drag is suppressed
- **WHEN** there is exactly one pane stack in the layout and that pane stack has exactly one pane tab
- **THEN** OpenMUX SHALL NOT start a pane-tab drag for that tab because no valid split or merge target exists

### Requirement: Dragging onto another pane tab strip SHALL merge the tab into that stack
The system SHALL recognize when a dragged pane tab is hovering over the tab strip of a different pane stack and offer a merge-into-stack drop mode distinct from the directional split mode.

#### Scenario: Hover over a different pane tab strip shows merge preview
- **WHEN** the user drags a pane tab over the tab strip region of a different pane stack
- **THEN** OpenMUX SHALL highlight the full width of that tab strip to indicate the tab will be appended to that stack

#### Scenario: Merge preview takes priority over edge-split preview
- **WHEN** the cursor is in the tab strip zone of a different pane stack
- **THEN** OpenMUX SHALL resolve the intent as merge rather than directional split

#### Scenario: Dropping on another pane tab strip appends tab to that stack
- **WHEN** the user drops a dragged pane tab while the merge preview is visible
- **THEN** OpenMUX SHALL move the pane tab into the target pane stack, appending it after its existing tabs

#### Scenario: Merged tab becomes focused in its new stack
- **WHEN** a pane tab is successfully merged into a different pane stack
- **THEN** OpenMUX SHALL focus the merged pane tab in the target pane stack

#### Scenario: Merge drop from a single-tab source collapses the source stack
- **WHEN** the user drags the only pane tab from its source stack and merges it into a different pane stack
- **THEN** OpenMUX SHALL collapse the empty source stack using normal split-tree layout normalization

#### Scenario: Merge drop preserves terminal session identity
- **WHEN** a pane tab is moved into a different stack by drag-to-merge
- **THEN** OpenMUX SHALL preserve the pane ID, session ID, terminal surface association, title, and terminal state for the merged pane tab

### Requirement: Single-tab source stacks SHALL be movable
The system SHALL allow dragging a pane tab out of a source stack even when that source stack contains only that pane tab, provided the drop target is valid and not the source stack.

#### Scenario: Moving only tab collapses source stack
- **WHEN** the user drags the only pane tab from its source stack and drops it onto a different valid target stack
- **THEN** OpenMUX SHALL move the pane tab into the new split and collapse the empty source stack using normal split-tree layout normalization

### Requirement: Drag-to-split SHALL remain app-level layout behavior
The system SHALL perform drag-to-split using OpenMUX workspace, tab, pane stack, pane, and session identifiers rather than terminal-runtime layout concepts.

#### Scenario: Terminal bridge remains layout-agnostic
- **WHEN** a pane tab is moved by drag-to-split
- **THEN** OpenMUX SHALL NOT require libghostty-specific layout state or expose libghostty types through workspace layout APIs
