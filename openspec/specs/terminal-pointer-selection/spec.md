# Capability: terminal-pointer-selection

## Purpose

Define pointer, scroll, focus, and selection behavior for runtime-backed and fallback terminal panes on macOS.
## Requirements
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

### Requirement: Pointer focus handoff preserves terminal events
OpenMUX SHALL focus panes on pointer interaction without swallowing the terminal pointer event that caused focus.

#### Scenario: Click focuses pane and reaches terminal
- **WHEN** the user clicks an unfocused runtime-backed terminal pane
- **THEN** OpenMUX SHALL focus that pane and SHALL also deliver the click to the runtime terminal surface

### Requirement: Terminal runtime owns selection for runtime panes
Runtime-backed terminal panes SHALL use terminal runtime selection behavior rather than selection state from a hidden overlay or AppShell text view.

#### Scenario: User selects terminal text
- **WHEN** the user drags to select text in a runtime-backed terminal pane
- **THEN** the terminal runtime SHALL own the selection state

#### Scenario: Copy observes runtime selection
- **WHEN** the user invokes Copy after selecting text in a runtime-backed terminal pane
- **THEN** OpenMUX SHALL copy the terminal runtime selection rather than overlay text selection

### Requirement: Pointer coordinates are terminal-relative
Runtime-backed terminal panes SHALL translate AppKit pointer coordinates into the coordinate space expected by the terminal runtime.

#### Scenario: Pointer moves inside terminal viewport
- **WHEN** the user moves the pointer inside a runtime-backed terminal pane
- **THEN** OpenMUX SHALL report runtime-relative pointer coordinates for the terminal viewport

#### Scenario: Pointer exits terminal viewport
- **WHEN** the pointer exits a runtime-backed terminal pane
- **THEN** OpenMUX SHALL notify the runtime that the pointer is outside the viewport

### Requirement: Fallback pointer behavior remains usable
Fallback terminal panes SHALL preserve basic focus, scroll, and visible-text selection behavior where runtime pointer APIs are unavailable.

#### Scenario: Fallback pane receives focus by click
- **WHEN** the user clicks a fallback terminal pane
- **THEN** OpenMUX SHALL focus that pane

#### Scenario: Fallback pane selects visible text
- **WHEN** the user drags across visible text in a fallback terminal pane
- **THEN** OpenMUX SHALL allow selecting visible text through the fallback text view

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

