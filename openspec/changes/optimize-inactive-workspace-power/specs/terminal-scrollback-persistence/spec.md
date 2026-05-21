## ADDED Requirements

### Requirement: Hidden live sessions SHALL remain eligible for scrollback persistence
The system SHALL keep live terminal sessions eligible for bounded scrollback capture even when their hosted presentation surface is not user-visible or is quiesced for power efficiency.

#### Scenario: Hidden session output can be persisted
- **WHEN** an inactive workspace terminal session produces output while its hosted surface is hidden
- **THEN** a scrollback-inclusive persistence pass can capture bounded output for that pane using the existing bridge-owned capture semantics

#### Scenario: Quiesced rendering does not fabricate scrollback
- **WHEN** a hidden hosted surface cannot provide terminal text during persistence
- **THEN** OpenMUX follows existing unavailable-capture behavior and does not fabricate scrollback merely because presentation rendering was quiesced

#### Scenario: Restored hidden session remains distinguishable
- **WHEN** a pane has restored historical scrollback and later produces live output while hidden
- **THEN** OpenMUX continues to distinguish restored historical context from live runtime text when forming persistence snapshots
