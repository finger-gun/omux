## MODIFIED Requirements

### Requirement: Runtime terminal view receives pointer events
Runtime-backed terminal panes SHALL forward pointer button, movement, drag, enter, exit, scroll, and pressure events to the terminal runtime. For pointer button press and release events, OpenMUX SHALL refresh the runtime pointer position before sending the button transition so terminal selection starts and ends from the current AppKit event location. A documented terminal text activation modifier-click MAY be handled by OpenMUX before forwarding when it successfully activates terminal text.

#### Scenario: Pointer click reaches runtime at current location
- **WHEN** the user clicks inside a runtime-backed terminal pane without the text activation modifier
- **THEN** OpenMUX SHALL deliver the current pointer position to the runtime before delivering the pointer press event

#### Scenario: Pointer drag exit preserves selection drag state
- **WHEN** the pointer exits a runtime-backed terminal pane while a mouse button remains pressed
- **THEN** OpenMUX SHALL NOT report the pointer as absent from the viewport before drag events can continue selection behavior

#### Scenario: Activation modifier click can be claimed
- **WHEN** the user performs a documented text activation modifier-click on a terminal token that OpenMUX successfully handles
- **THEN** OpenMUX MAY avoid sending that click as terminal input while preserving normal pointer behavior for unhandled clicks
