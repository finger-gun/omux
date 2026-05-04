## ADDED Requirements

### Requirement: Input-sent hook SHALL expose forwarded terminal input context
The hook foundation SHALL expose a `terminal-input-sent` input hook when OpenMUX successfully delivers explicit action-scoped terminal input to a live runtime surface.

#### Scenario: Input-sent hook receives context
- **WHEN** OpenMUX emits `terminal-input-sent`
- **THEN** the hook invocation includes category `input`, relevant workspace ID, tab ID, pane ID, session ID, and a payload containing `text`, `key`, `keyCode`, `modifiers`, `route`, and `source`

#### Scenario: Input-sent hook remains OpenMUX-native
- **WHEN** a hook handler receives `terminal-input-sent`
- **THEN** its payload describes OpenMUX terminal input context rather than raw terminal-engine structs or AppKit event objects

### Requirement: Input-sent hooks SHALL remain observational
The `terminal-input-sent` hook SHALL run through the existing external hook execution model and SHALL NOT block, approve, reject, or rewrite the input that triggered it.

#### Scenario: Hook failure does not cancel input
- **WHEN** a `terminal-input-sent` hook handler exits nonzero after input has been forwarded
- **THEN** OpenMUX reports the handler failure consistently with other hook failures and does not undo or cancel the terminal input

#### Scenario: Hook mutates through public automation
- **WHEN** a `terminal-input-sent` hook wants to react by focusing panes, sending text, fetching history, or notifying the user
- **THEN** it uses public `omux` commands or the local JSON-RPC control plane rather than hook stdout as an implicit command protocol
