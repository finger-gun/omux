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

#### Scenario: Shared host contains multiple vendor adapters
- **WHEN** OpenMUX ships an official AI status plugin
- **THEN** it may package Codex, Gemini, Claude, Copilot, and future tool adapters behind one shared `ai-status` host rather than requiring one plugin per vendor

#### Scenario: Official host lives in plugin registry repo
- **WHEN** OpenMUX ships an official installable `ai-status` host
- **THEN** that plugin package lives in the official plugin registry repository (`https://github.com/finger-gun/omux-plugins`, local checkout `/Users/lejahmie/projects/omux-plugins/`) rather than in this repository

#### Scenario: Core repo only owns host-side enablement
- **WHEN** OpenMUX changes are needed to support the `ai-status` host
- **THEN** this repository owns only the host-side integration work such as `omux pane-status`, plugin discovery/enablement, documentation, and shell rendering/tests, not the installable plugin package itself

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

### Requirement: Shared adapter hosts SHALL dedupe noisy observer signals
Shared AI/tool adapter hosts SHALL treat noisy title, notification, or transcript surfaces as best-effort observer inputs and emit pane-status updates only for meaningful state transitions.

#### Scenario: Spinner title frames do not flood pane-status
- **WHEN** a tool emits many title changes while staying in the same effective state
- **THEN** the shared host dedupes or debounces those raw signals instead of emitting one pane-status update per title frame

#### Scenario: Host synthesizes clear after signal loss
- **WHEN** a shared host no longer sees a supported tool identity for a pane after session end, explicit reset, or a configured stale timeout
- **THEN** it emits `clear` according to host policy rather than requiring vendors to expose a first-class clear event

### Requirement: Adapters SHALL NOT interfere with terminal input correctness
AI/tool status adapters SHALL NOT intercept, rewrite, block, or synthesize user keyboard input as part of status inference.

#### Scenario: IME and Option input remain terminal-owned
- **WHEN** a user types through IME composition, dead keys, compose sequences, or Option/right-Option layout text while an adapter is active
- **THEN** OpenMUX forwards terminal input through the normal input pipeline without adapter interception

#### Scenario: Adapter mutations are explicit
- **WHEN** an adapter wants to update OpenMUX state
- **THEN** it calls public automation such as pane-status rather than relying on hook stdout, terminal input capture, or private app APIs
