## ADDED Requirements

### Requirement: Pane headers provide context without boxing in terminals
Each pane stack SHALL provide header chrome that communicates pane context while keeping terminal content visually prioritized. Pane headers MUST remain slim and MUST NOT create a card-heavy or widget-like feeling around the terminal surface.

#### Scenario: Rendering a focused pane
- **WHEN** a pane is focused inside the workspace canvas
- **THEN** the pane header shows enough context to identify the pane while leaving the terminal body as the dominant surface

### Requirement: Pane stacks expose local tab context through dedicated pane chrome
Pane stacks with more than one local pane tab SHALL present local tab state through dedicated pane chrome rather than generic utility controls alone. The active local pane tab MUST be visually distinguishable from inactive tabs.

#### Scenario: Viewing a split region with multiple local pane tabs
- **WHEN** a split region contains multiple pane-local tabs
- **THEN** the pane header presents those tabs through dedicated local pane chrome with a clearly visible active state

### Requirement: Focus cues remain clear across split layouts
The workspace shell SHALL provide clear focus indication for pane stacks and active terminal targets across split layouts. Focus cues MUST remain visible without requiring heavy borders or visually noisy selection treatments.

#### Scenario: Moving focus between adjacent panes
- **WHEN** the user changes focus from one pane to another in a split workspace
- **THEN** the newly focused pane receives a clear visual focus cue and the previously focused pane returns to an unfocused state
