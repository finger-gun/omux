## ADDED Requirements

### Requirement: Keyboard input is normalized before dispatch
The system SHALL normalize macOS keyboard and text-input events into an OpenMUX input model before they are used for terminal dispatch, keybindings, or hooks.

#### Scenario: One input model serves multiple consumers
- **WHEN** a key event enters the application
- **THEN** the system converts it into a shared normalized representation before terminal or shell behavior is applied

### Requirement: International keyboard behavior is first-class
The system SHALL support ISO and EU keyboard layouts, including Alt/Option combinations, dead keys, and compose-related behavior, as a foundation requirement.

#### Scenario: International input is not treated as an edge case
- **WHEN** a user types with an ISO or EU keyboard layout
- **THEN** the system preserves intended text input and modifier semantics without requiring layout-specific hacks outside the input pipeline

### Requirement: Left and right modifiers remain distinguishable where required
The system SHALL preserve left/right modifier identity where needed to support correct terminal and shortcut behavior, including right-Option-sensitive flows.

#### Scenario: Right-Option behavior remains addressable
- **WHEN** right-Option behavior differs from left-Option behavior for a layout or workflow
- **THEN** the input model retains enough modifier information to support the distinction
