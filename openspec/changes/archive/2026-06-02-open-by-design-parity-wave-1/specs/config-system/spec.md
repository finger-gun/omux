## ADDED Requirements

### Requirement: Successful config reload completion SHALL be observable
The configuration system SHALL emit public OpenMUX-native observability for successful config apply/reload completion through both the hook surface and the control-plane event stream. This observability SHALL cover both explicit `omux config reload` requests and watched config/theme changes that reuse the same apply path.

#### Scenario: Explicit reload emits completion observability
- **WHEN** the user runs `omux config reload` and the apply/reload pass completes successfully
- **THEN** OpenMUX emits `config-reloaded` and `config.reloaded` with payload fields that identify the reload source and whether the effective configuration changed

#### Scenario: Watched change emits completion observability
- **WHEN** OpenMUX applies a watched config or active-theme change successfully
- **THEN** OpenMUX emits the same `config-reloaded` and `config.reloaded` contract used by the explicit reload command

#### Scenario: Failed reload emits no success-shaped completion signal
- **WHEN** a config apply/reload attempt fails validation and the previous effective configuration remains active
- **THEN** OpenMUX surfaces diagnostics without emitting `config-reloaded` or `config.reloaded`
