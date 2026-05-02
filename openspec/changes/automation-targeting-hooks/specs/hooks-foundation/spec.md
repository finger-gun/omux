## ADDED Requirements

### Requirement: Command-failed hook is emitted for nonzero command completions
The hook foundation SHALL expose a `command-failed` command hook when OpenMUX observes a command completion with a nonzero exit code.

#### Scenario: Nonzero command completion invokes failure hook
- **WHEN** OpenMUX observes a terminal command completion with a nonzero exit code
- **THEN** it emits `command-failed` with the same OpenMUX terminal context as the command completion

#### Scenario: Successful command does not invoke failure hook
- **WHEN** OpenMUX observes a terminal command completion with exit code zero
- **THEN** it does not emit `command-failed`

### Requirement: Command hooks include automation context
Command-related hooks SHALL include OpenMUX-native identifiers and command metadata needed for hooks to call public automation APIs without guessing targets.

#### Scenario: Command-started includes target and command
- **WHEN** OpenMUX emits `command-started`
- **THEN** the hook invocation includes workspace ID, tab ID, pane ID, session ID, and command text when available

#### Scenario: Command-finished includes completion metadata
- **WHEN** OpenMUX emits `terminal-command-finished`
- **THEN** the hook payload includes exit code, duration, command text when available, cwd when available, and bounded output context or an explicit unavailable value

#### Scenario: Command-failed includes failure metadata
- **WHEN** OpenMUX emits `command-failed`
- **THEN** the hook payload includes exit code, duration, command text when available, cwd when available, and bounded output context or an explicit unavailable value

### Requirement: Hooks mutate OpenMUX only through public actions
Hook handlers SHALL use `omux` or the local JSON-RPC control plane to mutate OpenMUX state; hook stdout SHALL NOT be treated as an implicit OpenMUX command protocol.

#### Scenario: Hook writes analysis back to terminal through CLI
- **WHEN** a hook wants to display analysis in the originating terminal
- **THEN** it calls the public send-text action with the session or pane ID from the hook payload

#### Scenario: Hook stdout remains handler output
- **WHEN** a hook writes to stdout
- **THEN** OpenMUX does not interpret that stdout as a split, focus, run, or send-text instruction
