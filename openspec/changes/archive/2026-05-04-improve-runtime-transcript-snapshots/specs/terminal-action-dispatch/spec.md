## MODIFIED Requirements

### Requirement: Command completion events include bounded output context
Terminal action dispatch SHALL attach bounded OpenMUX-owned output context to command completion events when available, and SHALL expose an explicit unavailable value when output context is not available. The output context SHALL be derived after terminal-engine action translation from OpenMUX-native runtime snapshot or history data, not from raw terminal-engine action payloads.

#### Scenario: Failure completion includes bounded output tail
- **WHEN** OpenMUX has a bounded output tail for a completed command
- **THEN** the command completion event exposes that tail as OpenMUX-owned text or an OpenMUX-owned output reference

#### Scenario: Output context is unavailable
- **WHEN** OpenMUX does not have output context for a completed command
- **THEN** the command completion event marks output context unavailable without buffering unbounded terminal history

#### Scenario: Output context uses bridge-owned snapshot text
- **WHEN** a command completion event is enriched after runtime action translation
- **THEN** OpenMUX derives output context from bounded OpenMUX-native snapshot or history data provided by the terminal bridge

#### Scenario: Output context does not leak terminal-engine payloads
- **WHEN** hooks or control-plane event subscribers consume command completion output context
- **THEN** they receive OpenMUX-native output context values rather than Ghostty action payloads, text structs, or point-selection types
