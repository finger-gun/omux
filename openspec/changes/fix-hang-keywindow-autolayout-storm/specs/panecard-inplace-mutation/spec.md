# panecard-inplace-mutation Specification

## Purpose
Eliminate unnecessary removal and re-addition of arranged subviews in `PaneCardView.configure` when the header view and pane renderer identity are unchanged, avoiding deep Auto Layout engine recursion that causes main-thread hangs.

## ADDED Requirements

### Requirement: PaneCardView configure SHALL mutate arranged subviews in-place when identity is stable
`PaneCardView.configure` SHALL only remove an arranged subview from the stack container when its identity changes from the previous configuration. When the header view is the same object reference and the pane renderer view is the same `NSView` instance, the subviews SHALL remain in the stack without removal.

#### Scenario: Header and renderer unchanged across reconfiguration
- **WHEN** `configure` is called with the same `headerView` object reference and the same `paneRenderer.rootPaneView` instance as the previous call
- **THEN** no arranged subview is removed from or re-added to the container, and the container's subview count does not change

#### Scenario: Header changes identity
- **WHEN** `configure` is called with a different `headerView` object reference than the previous call
- **THEN** only the old header view is removed from the container and the new header view is inserted in its position; the pane renderer view remains in-place

#### Scenario: Pane renderer changes identity
- **WHEN** `configure` is called with a different `paneRenderer.rootPaneView` instance than the previous call
- **THEN** only the old pane renderer view is removed from the container and the new pane renderer view is inserted in its position; the header view (if present) remains in-place

#### Scenario: Status text visibility changes without view teardown
- **WHEN** `configure` is called with a different `statusText` value than the previous call but unchanged header and renderer identity
- **THEN** the status label's `stringValue` and `isHidden` are updated in-place without removing or re-adding the status label view

### Requirement: In-place mutation SHALL preserve Auto Layout constraint graph integrity
When arranged subviews are mutated in-place rather than torn down, the resulting constraints SHALL produce the same visual layout as the previous full-teardown approach.

#### Scenario: Layout is identical after in-place mutation
- **WHEN** `configure` mutates subviews in-place instead of removing and re-adding them
- **THEN** the visual bounds of the `PaneCardView` container and its subviews match the bounds that would result from a full teardown-and-rebuild

#### Scenario: Focus ring and responder chain are unchanged
- **WHEN** `configure` mutates subviews in-place for a focused pane card
- **THEN** the focused pane renderer view remains connected to the responder chain without becoming first responder (no spurious focus changes)
