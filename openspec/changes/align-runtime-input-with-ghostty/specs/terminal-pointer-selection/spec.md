## ADDED Requirements

### Requirement: Runtime selection is visible to AppKit
Runtime-backed terminal panes SHALL expose Ghostty-owned selection state to AppKit text-input queries where the runtime selection APIs are available.

#### Scenario: Selected range reflects runtime selection
- **WHEN** a runtime-backed terminal pane has a terminal selection and AppKit asks for the selected range
- **THEN** OpenMUX SHALL return a range derived from the runtime selection instead of always returning an empty range

#### Scenario: Attributed substring reflects runtime selection
- **WHEN** a runtime-backed terminal pane has a terminal selection and AppKit asks for an attributed substring
- **THEN** OpenMUX SHALL return selected terminal text from the runtime without creating an independent OpenMUX selection model

#### Scenario: No runtime selection remains empty
- **WHEN** no runtime selection exists or the runtime selection APIs are unavailable
- **THEN** OpenMUX SHALL return empty selection values without fabricating selection text
