## ADDED Requirements

### Requirement: Hooks and plugins MAY act as tool-status bridges
The hook and plugin foundation SHALL allow external executable handlers to act as bridges between terminal tools and OpenMUX pane status by calling public automation commands.

#### Scenario: Hook marks tool output as needing input
- **WHEN** a hook or plugin detects that a terminal tool is waiting for user action in a pane
- **THEN** it can call `omux pane-status` with the pane ID from its environment, invocation payload, or discovery output

#### Scenario: Bridge uses public automation only
- **WHEN** a hook or plugin updates pane status
- **THEN** it uses `omux pane-status` or the local JSON-RPC control plane rather than private Swift APIs or hook stdout interpretation

### Requirement: Tool-status bridges SHALL receive enough OpenMUX context to target panes
Hook and plugin bridge patterns SHALL document how adapters discover or receive OpenMUX-native pane/session context for status updates.

#### Scenario: Wrapper launched inside pane uses environment identifiers
- **WHEN** a wrapper adapter runs inside an OpenMUX-launched terminal session
- **THEN** it can use `OMUX_PANE_ID` or `OMUX_SESSION_ID` to target status updates

#### Scenario: Hook handler uses invocation identifiers
- **WHEN** a hook handler reacts to a terminal event
- **THEN** it can use the hook invocation pane ID or session ID to target status updates

#### Scenario: External plugin uses discovery command
- **WHEN** a plugin is not launched from inside the target pane
- **THEN** it can use public discovery commands to find an explicit target instead of scraping OpenMUX UI

### Requirement: Tool-status bridge failures SHALL be isolated
Failures in tool-status bridge hooks or plugin adapters SHALL NOT break terminal sessions, block terminal input, or prevent later hook handlers from running.

#### Scenario: Adapter exits nonzero
- **WHEN** a tool-status adapter exits with a nonzero status
- **THEN** OpenMUX reports the failure consistently with external hook/plugin diagnostics and keeps the terminal session running

#### Scenario: Adapter cannot parse tool state
- **WHEN** an adapter cannot confidently infer a tool state
- **THEN** it leaves the current pane status unchanged or reports `indeterminate` according to adapter rules rather than fabricating a precise state
