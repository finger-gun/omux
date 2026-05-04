# terminal-scrollback-persistence Specification

## Purpose
TBD - created by archiving change persist-terminal-scrollback-history. Update Purpose after archive.
## Requirements
### Requirement: Pane scrollback SHALL be persisted as bounded historical context
The system SHALL persist bounded per-pane terminal scrollback text as historical context when workspace state is saved, subject to explicit size or line limits. Runtime-backed pane persistence SHALL use the bridge-owned bounded terminal text semantics used by live snapshots and history requests, and SHALL avoid persisting fabricated text when capture is unavailable.

#### Scenario: Scrollback snapshot is bounded
- **WHEN** a pane contains more terminal output than the configured persistence limit
- **THEN** OpenMUX persists only the bounded tail of that pane's scrollback

#### Scenario: Empty scrollback is omitted
- **WHEN** a pane has no available scrollback text
- **THEN** OpenMUX does not persist an empty or fabricated scrollback snapshot for that pane

#### Scenario: Unavailable runtime capture is omitted
- **WHEN** a runtime-backed pane cannot provide terminal text during workspace persistence
- **THEN** OpenMUX omits new persisted scrollback for that pane or preserves existing restored historical context without fabricating output

### Requirement: Restored scrollback SHALL NOT imply live session restoration
The system SHALL restore saved scrollback only as historical text context while launching a fresh terminal session for the pane. Restored historical context SHALL remain distinguishable from text captured from the fresh live runtime session.

#### Scenario: Restored pane starts fresh session with historical context
- **WHEN** OpenMUX restores a pane with saved scrollback
- **THEN** the pane starts a fresh shell session and makes the saved scrollback available as prior context rather than as output from the fresh process

#### Scenario: Running process state is not claimed
- **WHEN** saved scrollback contains output from a command that was running before quit
- **THEN** OpenMUX does not report or imply that the command, PTY, SSH connection, or TUI process has been restored

#### Scenario: Restored and live text stay distinguishable
- **WHEN** a restored pane later captures live runtime text from its fresh session
- **THEN** OpenMUX can distinguish that live text from the restored historical scrollback context when forming history or output-context values

### Requirement: Scrollback persistence SHALL remain local and bounded by default
The system SHALL store scrollback snapshots only in local OpenMUX persistence and SHALL avoid exposing persisted scrollback to hooks or external automation by default.

#### Scenario: Hooks do not receive persisted scrollback by default
- **WHEN** workspace or terminal hooks are emitted during restore
- **THEN** persisted scrollback text is not included in hook payloads unless a future explicit contract adds it

