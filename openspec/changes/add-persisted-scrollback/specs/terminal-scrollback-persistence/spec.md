## MODIFIED Requirements

### Requirement: Pane scrollback SHALL be persisted as bounded historical context
The system SHALL persist bounded per-pane terminal scrollback as historical context when workspace state is saved in scrollback-inclusive mode, subject to explicit configured size and line limits. Runtime-backed pane persistence SHALL use the bridge-owned bounded terminal text semantics used by live snapshots and history requests, SHALL preserve raw ANSI output where the bridge can provide it safely, and SHALL avoid persisting fabricated text when capture is unavailable. The default retained scrollback limit SHALL be 4,000 lines unless the user configures another valid limit.

#### Scenario: Scrollback snapshot is bounded
- **WHEN** a pane contains more terminal output than the configured persistence limit
- **THEN** OpenMUX persists only the bounded tail of that pane's scrollback

#### Scenario: Empty scrollback is omitted
- **WHEN** a pane has no available scrollback text
- **THEN** OpenMUX does not persist an empty or fabricated scrollback snapshot for that pane

#### Scenario: Unavailable runtime capture is omitted
- **WHEN** a runtime-backed pane cannot provide terminal text during workspace persistence
- **THEN** OpenMUX omits new persisted scrollback for that pane or preserves existing restored historical context without fabricating output

#### Scenario: Raw ANSI formatting is preserved
- **WHEN** captured scrollback includes ANSI color or styling escape sequences that are safe to replay
- **THEN** OpenMUX persists those escape sequences as part of the bounded historical payload

#### Scenario: Default scrollback retention is used
- **WHEN** the user has not configured a persisted scrollback line limit
- **THEN** OpenMUX bounds persisted scrollback to 4,000 lines and the built-in byte cap

### Requirement: Restored scrollback SHALL NOT imply live session restoration
The system SHALL restore saved scrollback only as historical context while launching a fresh terminal session for the pane. When visual replay is available, restored historical context SHALL be replayed into the fresh terminal before the first interactive shell prompt and SHALL remain distinguishable from text captured from the fresh live runtime session.

#### Scenario: Restored pane starts fresh session with historical context
- **WHEN** OpenMUX restores a pane with saved scrollback
- **THEN** the pane starts a fresh shell session and makes the saved scrollback available as prior context rather than restored process state

#### Scenario: Running process state is not claimed
- **WHEN** saved scrollback contains output from a command that was running before quit
- **THEN** OpenMUX does not report or imply that the command, PTY, SSH connection, or TUI process has been restored

#### Scenario: Restored and live text stay distinguishable
- **WHEN** a restored pane later captures live runtime text from its fresh session
- **THEN** OpenMUX can distinguish that live text from the restored historical scrollback context when forming history or output-context values

#### Scenario: Restored scrollback replays before prompt
- **WHEN** OpenMUX visually restores scrollback for a pane
- **THEN** the saved historical output is replayed before the first interactive shell prompt is shown

### Requirement: Scrollback persistence SHALL remain local and bounded by default
The system SHALL store scrollback snapshots only in local OpenMUX persistence, SHALL keep persisted scrollback bounded by configured line and byte limits, and SHALL avoid exposing persisted scrollback to hooks or external automation by default. Persistent workspace/session state and scrollback payloads SHALL be stored under OpenMUX-managed Application Support paths rather than long-term `UserDefaults` storage.

#### Scenario: Hooks do not receive persisted scrollback by default
- **WHEN** workspace or terminal hooks are emitted during restore
- **THEN** persisted scrollback text is not included in hook payloads unless a future explicit contract adds it

#### Scenario: Scrollback is stored locally
- **WHEN** OpenMUX persists pane scrollback
- **THEN** the payload is written only to local OpenMUX-managed storage

#### Scenario: Workspace state uses file-backed persistence
- **WHEN** OpenMUX saves durable workspace/session state
- **THEN** the canonical persisted state is written under Application Support using OpenMUX-managed files

## ADDED Requirements

### Requirement: Restored scrollback SHALL be visually replayed with ANSI reset protection
The system SHALL visually replay restored scrollback by launching a fresh terminal through an OpenMUX-owned pre-shell replay path that emits saved raw output, resets terminal formatting state, and then starts the user's shell. Replay SHALL NOT send the restored text as shell input and SHALL NOT add replay commands to shell history.

#### Scenario: Replay uses raw output before shell startup
- **WHEN** a restored pane has a replayable scrollback payload
- **THEN** OpenMUX emits the raw saved output before starting the user's interactive shell

#### Scenario: Replay resets formatting before prompt
- **WHEN** replay completes
- **THEN** OpenMUX emits terminal reset protection before the user's prompt can inherit restored styling or cursor state

#### Scenario: Replay file is cleaned up
- **WHEN** a replay file is consumed by the restored terminal wrapper
- **THEN** OpenMUX removes the replay file so restored scrollback is not left in temporary replay storage

### Requirement: Alternate-screen restoration SHALL be best-effort history
The system SHALL treat alternate-screen and full-screen TUI output as best-effort historical scrollback only. OpenMUX SHALL NOT claim to restore the alternate-screen application, process, cursor position, or private screen state.

#### Scenario: TUI process is not restored
- **WHEN** saved output came from a full-screen TUI or alternate-screen application
- **THEN** OpenMUX restores only safe historical output and starts a fresh shell session

#### Scenario: Unsafe alternate-screen replay is avoided
- **WHEN** captured output would leave the restored terminal in an unsafe or confusing control state
- **THEN** OpenMUX omits or bounds that replay rather than producing a broken prompt

### Requirement: Persisted scrollback SHALL be clearable by users
The system SHALL provide a CLI-accessible control-plane operation to clear persisted scrollback. Clearing history SHALL remove model-level restored scrollback for targeted panes, SHALL clear live screen/scrollback for running targeted panes when the terminal runtime supports it, SHALL locally clear the invoking pane's terminal buffer when the CLI is running inside a targeted OpenMUX-launched pane, SHALL remove unreferenced persisted scrollback payload files, and SHALL avoid immediately re-persisting unchanged live terminal text for panes whose history was just cleared.

#### Scenario: All persisted history is cleared
- **WHEN** the user runs the history clear command without a scope
- **THEN** OpenMUX clears persisted scrollback for every pane

#### Scenario: Persisted history is cleared by target scope
- **WHEN** the user runs the history clear command with a pane, pane-tab, tab, workspace, session, or focused-pane target
- **THEN** OpenMUX clears persisted scrollback only for panes in that target scope

#### Scenario: Unchanged live text is not immediately recaptured
- **WHEN** a pane's history is cleared while the live terminal still contains the same text
- **THEN** the next scrollback-inclusive persistence pass does not re-save that unchanged text as restored scrollback

#### Scenario: Repeated shell startup and prompt tail noise is not persisted
- **WHEN** scrollback capture contains repeated shell login banners or prompt-only tail lines from prior visual replays
- **THEN** OpenMUX stores a cleaned bounded payload that keeps the latest shell startup line, drops stale trailing prompt-only lines, and preserves non-prompt repeated output
