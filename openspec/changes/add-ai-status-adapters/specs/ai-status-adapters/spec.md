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

### Requirement: Adapters SHALL be host-owned and vendor-neutral
AI/tool status adapters SHALL run through a bundled OpenMUX `ai-status` host, external executables, hook handlers, or plugin commands rather than vendor integrations inside the OpenMUX app shell or terminal bridge.

#### Scenario: Bundled host contains multiple vendor adapters
- **WHEN** OpenMUX ships official AI status support
- **THEN** it packages Codex, Gemini, Claude, Copilot, and future tool adapters behind one bundled `ai-status` host rather than requiring one plugin per vendor

#### Scenario: Host uses public pane status reporting
- **WHEN** the bundled `ai-status` host maps vendor activity to OpenMUX state
- **THEN** it reports through the same validated pane-status control-plane path exposed to hooks and plugins

#### Scenario: Codex adapter uses external process boundary
- **WHEN** OpenMUX provides Codex status support
- **THEN** Codex-specific parsing, hook normalization, or wrapping lives in the `ai-status` adapter layer rather than in app-shell layout code

#### Scenario: Claude adapter can be added independently
- **WHEN** a Claude adapter is added later
- **THEN** it uses the same adapter reporting contract without requiring new shell chrome or terminal bridge APIs

### Requirement: AI-status CLI SHALL manage vendor hooks explicitly
The `omux` CLI SHALL expose `omux ai-status hooks setup|uninstall [codex|claude|gemini]` for explicit user-managed AI status hook installation.

#### Scenario: User installs all supported hooks
- **WHEN** the user runs `omux ai-status hooks setup`
- **THEN** OpenMUX installs only supported OpenMUX-owned hook entries for detected Codex, Claude, and Gemini configurations and reports any skipped vendors

#### Scenario: User installs one vendor hook
- **WHEN** the user runs `omux ai-status hooks setup codex`
- **THEN** OpenMUX updates only the Codex hook configuration needed to invoke the OpenMUX `ai-status` relay

#### Scenario: Claude setup follows conservative wrapper path
- **WHEN** the user runs `omux ai-status hooks setup claude`
- **THEN** OpenMUX configures Claude integration through wrapper-injected or guided hook setup rather than silently editing Claude-owned settings

#### Scenario: User uninstalls one vendor hook
- **WHEN** the user runs `omux ai-status hooks uninstall gemini`
- **THEN** OpenMUX removes only OpenMUX-owned Gemini hook entries and preserves user-authored Gemini settings

### Requirement: Vendor config edits SHALL be marker-owned
AI-status hook setup SHALL modify vendor configuration files only in response to an explicit user command and SHALL mark OpenMUX-owned entries so uninstall can remove them without deleting user entries.

#### Scenario: Setup never runs implicitly
- **WHEN** OpenMUX launches or restores a terminal pane
- **THEN** it does not edit Codex, Claude, or Gemini configuration unless the user invoked an `omux ai-status hooks setup` command

#### Scenario: Uninstall preserves foreign entries
- **WHEN** a vendor config contains both user-authored hook entries and OpenMUX-owned hook entries
- **THEN** `omux ai-status hooks uninstall <vendor>` removes only the entries identified by OpenMUX markers

#### Scenario: Managed edit is inspectable
- **WHEN** OpenMUX writes a vendor hook entry
- **THEN** the command references `omux ai-status hook --source <vendor> --event <event>` and includes an OpenMUX ownership marker compatible with that vendor config format

### Requirement: Vendor hook relay SHALL normalize stdin payloads
The `omux ai-status hook --source <vendor> --event <event>` command SHALL read the vendor hook payload from stdin, normalize it into an OpenMUX AI-status event, and report the resulting pane status through the public control plane.

#### Scenario: Codex permission hook maps to needs-input
- **WHEN** Codex invokes the relay with `--source codex --event PermissionRequest` and a valid permission payload on stdin
- **THEN** the host reports `needs-input` for the target pane with Codex source metadata

#### Scenario: Gemini tool hook maps to working
- **WHEN** Gemini invokes the relay with `--source gemini --event PreToolUse` and a valid tool payload on stdin
- **THEN** the host reports `working` or `indeterminate` for the target pane with Gemini source metadata

#### Scenario: Claude stop failure maps to error
- **WHEN** Claude invokes the relay with `--source claude --event StopFailure` and a valid failure payload on stdin
- **THEN** the host reports `error` for the target pane with Claude source metadata and an optional message

#### Scenario: Invalid hook payload is isolated
- **WHEN** the relay receives malformed JSON or an unsupported event
- **THEN** it reports a local diagnostic and does not block terminal input, mutate unrelated pane state, or require app-shell vendor logic

### Requirement: Adapters SHALL support hook, observer, and controlled-launch wrapper modes
The adapter contract SHALL allow hook adapters that receive vendor lifecycle payloads, observer adapters that infer status from title changes or bounded context, and wrapper adapters that launch a tool command and parse lifecycle or JSONL output.

#### Scenario: Wrapper adapter tracks process lifecycle
- **WHEN** a user runs a tool through a wrapper adapter
- **THEN** the adapter can report working status before launching the tool and idle or error status when the wrapped process exits

#### Scenario: JSONL wrapper maps structured events
- **WHEN** OpenMUX launches Codex, Gemini, or Claude through a JSONL-capable wrapper path
- **THEN** the adapter maps documented JSONL events to normalized pane status without relying on terminal-title text

#### Scenario: Hook adapter tracks interactive session
- **WHEN** a vendor hook invokes the OpenMUX relay during an interactive session
- **THEN** the adapter can report status without OpenMUX launching or wrapping the agent process

#### Scenario: Observer adapter uses bounded context
- **WHEN** an observer adapter needs terminal output to infer status
- **THEN** it uses bounded OpenMUX history or a tool-owned event/log source rather than unbounded terminal capture

#### Scenario: Passive title fallback remains best effort
- **WHEN** no OpenMUX-managed vendor hook is installed for a pane
- **THEN** the adapter may infer status from debounced terminal-title signals with lower confidence than hook or JSONL events

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

#### Scenario: Hooks do not approve terminal input
- **WHEN** a vendor hook relay runs for AI status detection
- **THEN** OpenMUX does not use that relay to intercept, approve, reject, or rewrite user keyboard input sent to the terminal
