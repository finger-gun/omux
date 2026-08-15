# workspace-render-reconciliation Delta Specification

## ADDED Requirements

### Requirement: Reconciliation SHALL be safe to invoke redundantly
The `refreshTerminalPresentation` and `reconcileLayoutView` paths SHALL be safe to invoke multiple times within a single event-loop turn without causing redundant full-hierarchy teardown of unchanged pane subviews.

#### Scenario: Redundant key-window refresh reuses existing views
- **WHEN** `refreshTerminalPresentation` is called for the same workspace with unchanged layout topology and pane identities as the previous call
- **THEN** `PaneCardView.configure` does not remove and re-add unchanged arranged subviews, avoiding Auto Layout engine recursion

#### Scenario: Post-refresh layout matches pre-refresh layout
- **WHEN** a redundant `refreshTerminalPresentation` call completes on an unchanged workspace
- **THEN** the visible pane card layouts, split positions, and pane renderer views are visually identical to the state before the call

## MODIFIED Requirements

### Requirement: Reconciled updates SHALL preserve interactive view state
For identity-stable panes, reconciled updates SHALL preserve responder/focus continuity and extension-pane runtime host state needed for interactive reading and editing workflows. Redundant reconciliation calls SHALL NOT tear down and recreate the subview hierarchy of identity-stable panes.

#### Scenario: Terminal focus survives status/content update
- **WHEN** a focused terminal pane receives non-structural workspace updates
- **THEN** the terminal pane remains the active input target after reconciliation

#### Scenario: Extension pane state survives non-structural update
- **WHEN** an extension pane remains identity-stable across a non-structural update
- **THEN** its host view state required for continuity (including scroll position) remains preserved

#### Scenario: Terminal focus survives redundant key-window refresh
- **WHEN** a focused terminal pane receives a redundant `refreshTerminalPresentation` call driven by a no-op key-window notification
- **THEN** the terminal pane remains the active input target with no view hierarchy teardown

#### Scenario: Extension pane state survives redundant key-window refresh
- **WHEN** an extension pane remains identity-stable across a redundant key-window refresh
- **THEN** its WKWebView and script message handler state remains intact without reload or teardown
