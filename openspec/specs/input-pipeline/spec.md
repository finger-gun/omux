# input-pipeline Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.

## Requirements

### Requirement: Keyboard input is normalized before dispatch
The system SHALL normalize macOS keyboard and text-input events into an OpenMUX input model before they are used for terminal dispatch, keybindings, hooks, or bridge-owned translation into a hosted libghostty surface.

#### Scenario: One input model serves multiple consumers
- **WHEN** a key event enters the application
- **THEN** the system converts it into a shared normalized representation before terminal or shell behavior is applied

### Requirement: International keyboard behavior is first-class
The system SHALL support ISO and EU keyboard layouts, including Alt/Option combinations, dead keys, and compose-related behavior, as a foundation requirement for both shell shortcuts and hosted libghostty pane input.

#### Scenario: International input is not treated as an edge case
- **WHEN** a user types with an ISO or EU keyboard layout
- **THEN** the system preserves intended text input and modifier semantics without requiring layout-specific hacks outside the input pipeline

### Requirement: Left and right modifiers remain distinguishable where required
The system SHALL preserve left/right modifier identity where needed to support correct terminal and shortcut behavior, including right-Option-sensitive flows that must survive delivery into a hosted libghostty surface.

#### Scenario: Right-Option behavior remains addressable
- **WHEN** right-Option behavior differs from left-Option behavior for a layout or workflow
- **THEN** the input model retains enough modifier information to support the distinction through terminal dispatch

### Requirement: Terminal editing keys SHALL stay distinct from text insertion
The system SHALL preserve the distinction between text-producing input and terminal-control input such as return, delete, arrows, and paste so live sessions receive the intended behavior.

#### Scenario: Editing keys do not become plain text
- **WHEN** a user presses return, backspace, or an arrow key in a focused terminal pane
- **THEN** the system routes the normalized event as terminal control input rather than inserting literal characters into the pane text model
