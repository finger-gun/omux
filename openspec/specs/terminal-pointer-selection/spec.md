# Capability: terminal-pointer-selection

## Purpose

Define pointer, scroll, focus, and selection behavior for runtime-backed and fallback terminal panes on macOS.

## Requirements

### Requirement: Runtime terminal view receives pointer events
Runtime-backed terminal panes SHALL forward pointer button, movement, drag, enter, exit, scroll, and pressure events to the terminal runtime.

#### Scenario: Pointer click reaches runtime
- **WHEN** the user clicks inside a runtime-backed terminal pane
- **THEN** OpenMUX SHALL deliver the pointer event to the runtime terminal surface

#### Scenario: Pointer drag reaches runtime
- **WHEN** the user drags inside a runtime-backed terminal pane
- **THEN** OpenMUX SHALL deliver pointer movement and button state to the runtime terminal surface

#### Scenario: Scroll reaches runtime
- **WHEN** the user scrolls inside a runtime-backed terminal pane
- **THEN** OpenMUX SHALL deliver scroll delta, precision, and momentum information that is available from AppKit to the runtime terminal surface

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
