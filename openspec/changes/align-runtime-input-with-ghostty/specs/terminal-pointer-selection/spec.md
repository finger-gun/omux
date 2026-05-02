## MODIFIED Requirements

### Requirement: Runtime terminal view receives pointer events
Runtime-backed terminal panes SHALL forward pointer button, movement, drag, enter, exit, scroll, and pressure events to the terminal runtime. For pointer button press and release events, OpenMUX SHALL refresh the runtime pointer position before sending the button transition so terminal selection starts and ends from the current AppKit event location.

#### Scenario: Pointer click reaches runtime at current location
- **WHEN** the user clicks inside a runtime-backed terminal pane
- **THEN** OpenMUX SHALL deliver the current pointer position to the runtime before delivering the pointer press event

#### Scenario: Pointer drag exit preserves selection drag state
- **WHEN** the pointer exits a runtime-backed terminal pane while a mouse button remains pressed
- **THEN** OpenMUX SHALL NOT report the pointer as absent from the viewport before drag events can continue selection behavior

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
