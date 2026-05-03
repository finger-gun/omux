## ADDED Requirements

### Requirement: Hook handlers can fetch bounded terminal history through public automation
Hook handlers SHALL be able to fetch bounded terminal history for relevant OpenMUX panes by invoking the public `omux history` CLI or equivalent local control-plane operation with identifiers from hook invocation payloads.

#### Scenario: Command hook fetches originating pane history
- **WHEN** a command-related hook receives a pane ID in its invocation payload
- **THEN** the hook handler can call `omux history <pane-id>` to fetch bounded history for that pane without depending on private app internals

#### Scenario: Hook script fetches structured history
- **WHEN** a hook handler needs machine-readable pane history
- **THEN** it can request JSON output from the public history command or control-plane operation

### Requirement: Hook invocations do not automatically include full scrollback
OpenMUX SHALL NOT attach full pane scrollback/history text to every hook invocation payload by default. Hook payloads SHALL continue to provide OpenMUX-native identifiers and bounded event context so handlers can opt in to explicit history reads.

#### Scenario: Hook payload stays lightweight
- **WHEN** OpenMUX invokes a hook for terminal activity
- **THEN** the payload includes target identifiers but does not automatically include full terminal scrollback

#### Scenario: Handler opts in to history access
- **WHEN** a hook handler needs additional output context beyond the invocation payload
- **THEN** it explicitly calls the public history surface for the target pane or workspace
