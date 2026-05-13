## ADDED Requirements

### Requirement: CLI interactive pickers SHALL share a common engine
Interactive CLI picker flows SHALL use a shared engine for terminal raw-mode handling, viewport rendering, search filtering, and key-event reading.

#### Scenario: Theme and plugin pickers use shared key handling
- **WHEN** users navigate interactive theme and plugin pickers
- **THEN** both pickers process arrow, enter, cancel, backspace, and character input through the same engine behavior

#### Scenario: Shared engine preserves terminal cleanup guarantees
- **WHEN** picker interaction exits by selection, cancel, or error
- **THEN** terminal mode and cursor visibility are restored reliably
