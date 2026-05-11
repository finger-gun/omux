## ADDED Requirements

### Requirement: AI/tool status adapters SHALL report normalized pane status
The system SHALL define external AI/tool status adapters that translate tool-specific activity into OpenMUX-native pane status states without exposing vendor-specific state directly to shell chrome.

#### Scenario: Adapter reports working state
- **WHEN** an adapter observes a supported tool performing work in a target pane
- **THEN** it reports `working` or `indeterminate` pane status for that pane through the public OpenMUX automation surface

#### Scenario: Adapter reports user attention state
- **WHEN** an adapter observes a supported tool waiting for user input, approval, or selection
- **THEN** it reports `needs-input` pane status for that pane through the public OpenMUX automation surface

#### Scenario: Adapter reports completion state
- **WHEN** an adapter observes a supported tool complete successfully
- **THEN** it reports `idle` pane status or clears pane status according to adapter configuration

#### Scenario: Adapter reports failure state
- **WHEN** an adapter observes a supported tool fail or exit unsuccessfully
- **THEN** it reports `error` pane status with tool-owned source metadata and an optional message

### Requirement: Adapters SHALL be external and vendor-neutral
AI/tool status adapters SHALL run as external executables, hook handlers, or plugin commands rather than in-process vendor integrations inside the OpenMUX app shell.

#### Scenario: Codex adapter uses external process boundary
- **WHEN** OpenMUX provides Codex status support
- **THEN** Codex-specific parsing or wrapping lives in an adapter executable or plugin command rather than in app-shell layout code

#### Scenario: Claude adapter can be added independently
- **WHEN** a Claude adapter is added later
- **THEN** it uses the same adapter reporting contract without requiring new shell chrome or terminal bridge APIs

### Requirement: Adapters SHALL support wrapper and observer modes
The adapter contract SHALL allow both wrapper adapters that launch a tool command and observer adapters that infer status from bounded history, local logs, or tool event output.

#### Scenario: Wrapper adapter tracks process lifecycle
- **WHEN** a user runs a tool through a wrapper adapter
- **THEN** the adapter can report working status before launching the tool and idle or error status when the wrapped process exits

#### Scenario: Observer adapter uses bounded context
- **WHEN** an observer adapter needs terminal output to infer status
- **THEN** it uses bounded OpenMUX history or a tool-owned event/log source rather than unbounded terminal capture

### Requirement: Adapters SHALL remain opt-in and lightweight
The system SHALL avoid starting AI/tool status adapters unless the user invokes, installs, or enables the relevant adapter.

#### Scenario: No configured adapter has no background process
- **WHEN** no AI/tool status adapter is configured or invoked
- **THEN** OpenMUX does not start a long-lived adapter process for that tool

#### Scenario: Adapter polling is bounded
- **WHEN** an observer adapter polls for status
- **THEN** it uses bounded intervals and bounded input data so adapter activity does not degrade terminal performance

### Requirement: Adapters SHALL NOT interfere with terminal input correctness
AI/tool status adapters SHALL NOT intercept, rewrite, block, or synthesize user keyboard input as part of status inference.

#### Scenario: IME and Option input remain terminal-owned
- **WHEN** a user types through IME composition, dead keys, compose sequences, or Option/right-Option layout text while an adapter is active
- **THEN** OpenMUX forwards terminal input through the normal input pipeline without adapter interception

#### Scenario: Adapter mutations are explicit
- **WHEN** an adapter wants to update OpenMUX state
- **THEN** it calls public automation such as pane-status rather than relying on hook stdout, terminal input capture, or private app APIs
