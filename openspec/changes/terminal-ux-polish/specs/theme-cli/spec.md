## ADDED Requirements

### Requirement: Interactive theme picker remains visible in small terminals
The CLI SHALL keep the highlighted theme visible when `omux theme` runs in an interactive terminal whose visible row count is smaller than the number of available themes.

#### Scenario: Selection stays inside viewport
- **WHEN** `omux theme` displays more themes than fit in the terminal and the user moves the highlighted selection downward
- **THEN** the picker updates the visible theme range so the highlighted selection remains visible

#### Scenario: Scriptable theme selection remains unchanged
- **WHEN** the user runs `omux theme <name>` or `omux theme list`
- **THEN** the CLI SHALL NOT open the interactive viewport picker
