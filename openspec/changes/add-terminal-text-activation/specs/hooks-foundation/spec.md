## ADDED Requirements

### Requirement: Hooks SHALL observe terminal text activation
The hooks system SHALL allow input hooks to observe terminal text activation events emitted by OpenMUX.

#### Scenario: Input hook receives terminal text activation
- **WHEN** a user activates terminal text with the documented modifier gesture
- **THEN** OpenMUX invokes matching input hooks named `terminal-text-activated` with OpenMUX-native activation payload fields
