# hooks-foundation Specification

## Purpose
TBD - created by archiving change macos-foundation. Update Purpose after archive.
## Requirements
### Requirement: The foundation defines stable hook categories
The system SHALL define initial hook categories for lifecycle, session, command, UI, and input events.

#### Scenario: Extension points are named and intentional
- **WHEN** a future feature or plugin needs to react to application behavior
- **THEN** it can target a documented hook category instead of relying on incidental internal coupling

### Requirement: Hooks are contracts, not implementation leaks
The system SHALL define hooks as stable behavioral contracts around OpenMUX concepts rather than exposing arbitrary internal objects or terminal-engine internals.

#### Scenario: Hook consumers depend on stable semantics
- **WHEN** a hook is invoked for external automation or future plugin behavior
- **THEN** the hook payload and lifecycle semantics are expressed in OpenMUX-native terms

### Requirement: External extensibility precedes embedded runtimes
The system SHALL support a foundation that is compatible with external hooks and plugin processes before introducing in-process scripting or WASM runtimes.

#### Scenario: Initial extensibility does not require embedded runtimes
- **WHEN** the foundation is implemented for first-phase automation
- **THEN** it can support external hook execution without requiring an embedded plugin engine inside the app process

### Requirement: Hook payloads support structured OpenMUX-native values
The hook foundation SHALL support structured payload values for hook invocations so terminal automation events can carry typed numbers, booleans, strings, arrays, objects, and nulls without flattening them to string-only metadata. Hook payload values SHALL be expressed in OpenMUX-native terms.

#### Scenario: Command-finished hook carries typed fields
- **WHEN** OpenMUX emits a hook for a terminal command-finished event
- **THEN** the hook payload can include typed fields such as numeric exit code and numeric duration without requiring string parsing by hook consumers

#### Scenario: Hook payload stays OpenMUX-native
- **WHEN** a hook consumer receives a payload derived from terminal action dispatch
- **THEN** the payload fields describe OpenMUX pane/session behavior rather than raw Ghostty action tags or Ghostty-owned structs

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

### Requirement: User hook directories SHALL register executable handlers by hook name
OpenMUX SHALL discover user hook handlers from direct child directories under `~/.omux/hooks/`, where each child directory name is a hook name and each executable regular file inside that directory is a handler for that hook.

#### Scenario: Executable handler is registered for matching hook
- **WHEN** `~/.omux/hooks/terminal-command-finished/10-notify` exists as an executable regular file
- **THEN** OpenMUX registers it as a handler for the `terminal-command-finished` hook

#### Scenario: Missing hooks directory is inert
- **WHEN** `~/.omux/hooks/` does not exist
- **THEN** OpenMUX starts with no user hook handlers and does not report a fatal error

### Requirement: Hook handlers SHALL be language-neutral executables
OpenMUX SHALL execute discovered hook handlers as executable files rather than interpreting them as a specific scripting language.

#### Scenario: Shell script handler uses its shebang
- **WHEN** an executable hook handler starts with `#!/usr/bin/env bash`
- **THEN** OpenMUX launches the handler directly and lets the operating system resolve the script runtime

#### Scenario: Deno TypeScript handler uses its shebang
- **WHEN** an executable hook handler starts with `#!/usr/bin/env -S deno run`
- **THEN** OpenMUX launches the handler directly without embedding Deno or treating TypeScript as a required hook format

### Requirement: Hook discovery SHALL ignore inactive entries
OpenMUX SHALL ignore hidden entries, non-executable files, and subdirectories inside hook-name directories during user hook discovery.

#### Scenario: Non-executable note is ignored
- **WHEN** `~/.omux/hooks/terminal-command-finished/README.md` exists without executable permissions
- **THEN** OpenMUX does not register it as a hook handler

#### Scenario: Hidden file is ignored
- **WHEN** `~/.omux/hooks/terminal-command-finished/.disabled` exists and is executable
- **THEN** OpenMUX does not register it as a hook handler

### Requirement: Multiple handlers for one hook SHALL run deterministically
OpenMUX SHALL run all registered handlers for a matching hook in lexicographic filename order within that hook's user directory.

#### Scenario: Numeric prefixes control order
- **WHEN** `~/.omux/hooks/terminal-command-finished/10-log` and `~/.omux/hooks/terminal-command-finished/20-notify` are both executable
- **THEN** OpenMUX runs `10-log` before `20-notify` for a `terminal-command-finished` invocation

### Requirement: User hook handlers SHALL receive structured invocation JSON
OpenMUX SHALL pass the full OpenMUX-native hook invocation to each user hook handler as JSON on stdin.

#### Scenario: Command-finished handler receives exit metadata
- **WHEN** OpenMUX invokes `terminal-command-finished` for a completed terminal command with exit code `1`
- **THEN** the handler stdin includes JSON with `name` set to `terminal-command-finished`, `category` set to `command`, the relevant workspace/tab/pane/session identifiers when available, and `payload.exitCode` set to `1`

### Requirement: User hook failures SHALL NOT stop later matching handlers
OpenMUX SHALL isolate user hook handler failures so one failing handler does not prevent later matching handlers from running and does not fail the underlying OpenMUX action.

#### Scenario: Failed first handler does not block second handler
- **WHEN** two executable handlers are registered for `terminal-command-finished` and the first handler exits non-zero
- **THEN** OpenMUX still runs the second handler for the same invocation and reports the first handler failure as a diagnostic warning

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

### Requirement: Hooks SHALL observe terminal text activation
The hooks system SHALL allow input hooks to observe terminal text activation events emitted by OpenMUX.

#### Scenario: Input hook receives terminal text activation
- **WHEN** a user activates terminal text with the documented modifier gesture
- **THEN** OpenMUX invokes matching input hooks named `terminal-text-activated` with OpenMUX-native activation payload fields

### Requirement: Registry-installed hooks SHALL use user hook directories
Registry-installed hook packages SHALL install executable handlers into the existing user hook directory layout under `~/.omux/hooks/<hook-name>/` and SHALL NOT introduce a separate runtime hook discovery path.

#### Scenario: Installed hook is locally discoverable
- **WHEN** OpenMUX installs a registry hook package for `terminal-command-finished`
- **THEN** the installed executable handlers appear under `~/.omux/hooks/terminal-command-finished/` and are discovered by the existing user hook discovery contract

#### Scenario: Runtime does not fetch registries
- **WHEN** OpenMUX emits a hook invocation
- **THEN** hook execution uses locally discovered handlers and does not contact remote registries

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

### Requirement: Hooks SHALL observe workspace restore lifecycle
The hook foundation SHALL expose a `workspace-restored` lifecycle hook when OpenMUX successfully restores a workspace through the shared restore flow.

#### Scenario: Restore emits workspace-restored hook
- **WHEN** a workspace restore action succeeds
- **THEN** matching lifecycle hooks receive `workspace-restored` with the restored workspace identifier and restore-context payload fields when available

### Requirement: Hooks SHALL observe extension-pane lifecycle transitions
The hook foundation SHALL expose stable hooks for successful extension-pane lifecycle transitions: `extension-pane-created`, `extension-pane-updated`, and `extension-pane-closed`.

#### Scenario: Extension pane create emits hook
- **WHEN** an extension pane is created successfully
- **THEN** matching hooks receive `extension-pane-created` with workspace, tab, pane, plugin, and content-kind context when available

#### Scenario: Extension pane update emits hook
- **WHEN** an extension pane update succeeds
- **THEN** matching hooks receive `extension-pane-updated` identifying the updated pane and owning plugin

#### Scenario: Extension pane close emits hook
- **WHEN** an extension pane is closed successfully
- **THEN** matching hooks receive `extension-pane-closed` identifying the closed pane and owning plugin

### Requirement: Hooks SHALL observe pane status updates
The hook foundation SHALL expose a `pane-status-updated` hook when OpenMUX successfully sets, changes, or clears transient pane status through its public pane-status path.

#### Scenario: Pane status set emits hook
- **WHEN** OpenMUX records a working, idle, needs-input, or error pane status successfully
- **THEN** matching hooks receive `pane-status-updated` with the resolved pane context and normalized status payload

#### Scenario: Pane status clear emits hook
- **WHEN** OpenMUX clears pane status successfully
- **THEN** matching hooks receive `pane-status-updated` with the resolved pane context and a payload that explicitly indicates the cleared state

### Requirement: Hooks SHALL observe successful config reload completion
The hook foundation SHALL expose a `config-reloaded` lifecycle hook when OpenMUX successfully completes a config apply/reload pass through either explicit command invocation or watched file changes.

#### Scenario: Explicit reload emits config hook
- **WHEN** the user runs `omux config reload` and the apply/reload pass succeeds
- **THEN** matching hooks receive `config-reloaded` with source metadata identifying command-triggered reload

#### Scenario: Watched reload emits config hook
- **WHEN** OpenMUX applies a valid watched config or theme-file change successfully
- **THEN** matching hooks receive `config-reloaded` with source metadata identifying the watched reload path

