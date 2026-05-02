## ADDED Requirements

### Requirement: Command completion events carry OpenMUX-owned command context
Terminal action dispatch SHALL enrich command completion events with OpenMUX-owned command context when that context is available, without exposing terminal-engine payload structs outside the terminal bridge boundary.

#### Scenario: Command completion includes known command text
- **WHEN** a command completion event corresponds to a command OpenMUX sent through run-command
- **THEN** the OpenMUX-native event includes that command text

#### Scenario: Unknown command text is explicit
- **WHEN** command text is not available for a completion event
- **THEN** the OpenMUX-native event represents the command text as unavailable instead of fabricating a value

### Requirement: Command completion events include bounded output context
Terminal action dispatch SHALL attach bounded OpenMUX-owned output context to command completion events when available, and SHALL expose an explicit unavailable value when output context is not available.

#### Scenario: Failure completion includes bounded output tail
- **WHEN** OpenMUX has a bounded output tail for a completed command
- **THEN** the command completion event exposes that tail as OpenMUX-owned text or an OpenMUX-owned output reference

#### Scenario: Output context is unavailable
- **WHEN** OpenMUX does not have output context for a completed command
- **THEN** the command completion event marks output context unavailable without buffering unbounded terminal history

### Requirement: Command failure is derived after terminal-engine translation
The system SHALL derive command-failure automation events from OpenMUX-native command completion data after terminal-engine action translation.

#### Scenario: Failure derivation avoids Ghostty leakage
- **WHEN** the app shell or hooks consume command-failure information
- **THEN** they consume OpenMUX-native exit code, duration, command, cwd, and output-context values rather than raw Ghostty action payloads
