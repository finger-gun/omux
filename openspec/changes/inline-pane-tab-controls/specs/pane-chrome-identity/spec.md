## ADDED Requirements

### Requirement: Pane chrome SHALL keep pane-tab controls attached to tab identity
Pane chrome SHALL present pane-local tab create and close controls as part of the pane-tab strip rather than as a separate trailing control group when those controls operate on pane-local tabs.

#### Scenario: Pane-tab controls are visually scoped to pane tabs
- **WHEN** a pane header renders local pane tabs and pane-tab controls
- **THEN** the add control and per-tab close controls appear within the tab strip so their scope is visually tied to local pane tabs

#### Scenario: Pane header avoids duplicate close affordance for focused local tab
- **WHEN** per-tab close controls are rendered for closable local pane tabs
- **THEN** the pane header does not also render a separate generic close-focused-pane-tab button for the same operation
